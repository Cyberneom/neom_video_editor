import {
  ALL_FORMATS, BufferSource, Input, Output, BufferTarget, Mp4OutputFormat,
  Conversion, Quality, canEncodeVideo, canEncodeAudio,
} from 'mediabunny';
import { opacityAtFrame, sourceFrameAtOutputTime, validateRecipe } from './recipe_math.js';

const sessions = new Map();
const MAX_INPUT_BYTES = 256 * 1024 * 1024;
const aborted = () => new Error('Exportación cancelada');
function check(session) {
  if (session.abort.signal.aborted) throw aborted();
}
async function sourceBytes(bytes, uri, session) {
  if (bytes) {
    if (bytes.byteLength > MAX_INPUT_BYTES) throw new Error('El vídeo supera el límite web de 256 MiB.');
    return bytes;
  }
  const url = new URL(uri, document.baseURI);
  if (!['http:', 'https:', 'blob:'].includes(url.protocol)) {
    throw new Error('Abre un archivo local o una URL HTTP/HTTPS accesible con CORS.');
  }
  const response = await fetch(url, { signal: session.abort.signal });
  if (!response.ok) throw new Error(`No se pudo leer el vídeo: HTTP ${response.status}.`);
  const size = Number(response.headers.get('content-length'));
  if (size > MAX_INPUT_BYTES) throw new Error('El vídeo supera el límite web de 256 MiB.');
  const chunks = [];
  let total = 0;
  const reader = response.body.getReader();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > MAX_INPUT_BYTES) throw new Error('El vídeo supera el límite web de 256 MiB.');
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  }
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
  return result;
}

async function begin(id, bytes, uri, recipeJson) {
  if (!globalThis.isSecureContext || !globalThis.VideoEncoder || !globalThis.VideoDecoder) {
    throw new Error('Este navegador no dispone de WebCodecs en un contexto seguro. Usa HTTPS o localhost con un navegador compatible.');
  }
  if (!globalThis.OffscreenCanvas || !globalThis.createImageBitmap) {
    throw new Error('Este navegador no dispone de las funciones de composición necesarias.');
  }
  const recipe = JSON.parse(recipeJson);
  const timing = validateRecipe(recipe);
  const session = { abort: new AbortController(), input: null, conversion: null, recipe, ...timing };
  sessions.set(id, session);
  try {
    const data = await sourceBytes(bytes, uri, session);
    check(session);
    const input = session.input = new Input({ source: new BufferSource(data), formats: ALL_FORMATS });
    const videoTracks = await input.getVideoTracks();
    const audioTracks = await input.getAudioTracks();
    if (videoTracks.length !== 1) throw new Error('La exportación web requiere exactamente una pista de vídeo.');
    const video = videoTracks[0];
    const width = await video.getDisplayWidth(), height = await video.getDisplayHeight();
    if (width % 2 || height % 2) throw new Error('H.264 requiere dimensiones pares; el vídeo no se redimensionará automáticamente.');
    if (width * height > 3840 * 2160) throw new Error('La exportación web admite hasta 8,3 megapíxeles por fotograma; el vídeo no se reducirá automáticamente.');
    const decoder = await video.getDecoderConfig();
    if (['pq', 'hlg', 'smpte2084', 'arib-std-b67'].includes(decoder?.colorSpace?.transfer)) {
      throw new Error('Este exportador compone títulos en SDR. Los vídeos HDR requieren conversión de color antes de exportar.');
    }
    if (!await video.canDecode()) throw new Error('El navegador no puede decodificar el códec de este vídeo.');
    if (!await canEncodeVideo('avc', { width, height, frameRate: timing.fps, quality: new Quality('high') })) {
      throw new Error(`El navegador no puede codificar H.264 a ${width} × ${height}. No se generará un archivo con otro formato.`);
    }
    for (const track of audioTracks) {
      if (!await track.canDecode()) throw new Error('El navegador no puede decodificar una pista de audio; se cancela para no perderla.');
      if (!await canEncodeAudio('aac', {
        numberOfChannels: await track.getNumberOfChannels(), sampleRate: await track.getSampleRate(),
        quality: new Quality('high'),
      })) throw new Error('El navegador no puede codificar una pista de audio a AAC; se cancela para no perderla.');
    }
    const duration = await video.computeDuration();
    if (timing.end > duration + 1e-4 || timing.start >= duration) {
      throw new Error('El rango de la receta supera la duración real del vídeo.');
    }
    Object.assign(session, { width, height, audioTracks: audioTracks.length });
    check(session);
    return JSON.stringify({ width, height, audioTracks: audioTracks.length, duration });
  } catch (error) {
    await dispose(id);
    throw error;
  }
}

async function render(id, titlePng, onProgress) {
  const session = sessions.get(id);
  if (!session) throw aborted();
  check(session);
  const { input, recipe, width, height, fps, start, end } = session;
  const canvas = new OffscreenCanvas(width, height);
  const context = canvas.getContext('2d', { alpha: false, colorSpace: 'srgb' });
  if (!context) throw new Error('El navegador no pudo crear la superficie de composición.');
  const title = titlePng?.byteLength ? await createImageBitmap(new Blob([titlePng], { type: 'image/png' })) : null;
  const target = new BufferTarget();
  const output = new Output({ format: new Mp4OutputFormat({ fastStart: 'in-memory' }), target });
  let frameCount = 0;
  try {
    const conversion = session.conversion = await Conversion.init({
      input, output, tracks: 'all', trim: { start, end }, copy: false, showWarnings: false,
      // Re-encoding selects the range without copying outside keyframe/packet
      // boundaries. AAC encoder padding can extend the final audio track.
      // Sample timestamps passed to process are relative to the trimmed output.
      video: {
        codec: 'avc', quality: new Quality('high'), frameRate: fps,
        allowTransformationMetadata: false, forceTranscode: true,
        process: async sample => {
          check(session);
          context.globalAlpha = 1;
          sample.draw(context, 0, 0, width, height);
          if (title) {
            const frame = sourceFrameAtOutputTime(sample.timestamp, recipe);
            context.globalAlpha = opacityAtFrame(recipe.opacityKeys, frame);
            context.drawImage(title, 0, 0, width, height);
            context.globalAlpha = 1;
          }
          // Give cancellation and the Flutter progress UI time to run.
          if (++frameCount % 8 === 0) await new Promise(resolve => setTimeout(resolve, 0));
          return canvas;
        },
        processedWidth: width, processedHeight: height,
      },
      audio: { codec: 'aac', quality: new Quality('high'), forceTranscode: true },
    });
    if (!conversion.isValid || conversion.discardedTracks.length) {
      const reasons = conversion.discardedTracks.map(track => track.reason).join(', ');
      throw new Error(`No se pueden preservar todas las pistas (${reasons || 'conversión incompatible'}).`);
    }
    conversion.onProgress = progress => onProgress(Math.max(0, Math.min(.99, progress)));
    check(session);
    await conversion.execute();
    check(session);
    if (!target.buffer || target.buffer.byteLength < 12 || frameCount === 0) {
      throw new Error('El exportador no generó un MP4 válido.');
    }
    const bytes = new Uint8Array(target.buffer);
    if (String.fromCharCode(...bytes.subarray(4, 8)) !== 'ftyp') throw new Error('Contenedor de salida inválido.');
    onProgress(1);
    return bytes;
  } catch (error) {
    if (session.cancelPromise) await session.cancelPromise;
    else if (output.state !== 'finalized' && output.state !== 'canceled') await output.cancel().catch(() => {});
    throw error;
  } finally {
    title?.close();
    canvas.width = canvas.height = 0;
    await dispose(id);
  }
}

function cancel(id) {
  const session = sessions.get(id);
  if (!session) return;
  session.abort.abort();
  // execute() can currently be draining an encoder. cancel() unblocks its pumps.
  if (session.conversion) session.cancelPromise ??= session.conversion.cancel().catch(() => {});
}
async function dispose(id) {
  const session = sessions.get(id);
  if (!session) return;
  sessions.delete(id);
  session.abort.abort();
  if (session.conversion && session.conversion.state !== 'done') {
    session.cancelPromise ??= session.conversion.cancel().catch(() => {});
    await session.cancelPromise;
  }
  session.input?.dispose();
}

// A late script response after a timed-out load must not replace live sessions.
globalThis.neomVideoExport ??= { version: '1.0.0', mediabunnyVersion: '1.61.4', begin, render, cancel, dispose };
