// Open Neom wrapper; no Artcraft engine code is copied into this adapter.
// Recipe v1 uses linear opacity keys, matching EffectScalarTrack's defaults.
export function opacityAtFrame(keys, frame) {
  if (!keys.length) return 1;
  if (frame <= keys[0].frame) return keys[0].value;
  for (let i = 1; i < keys.length; i++) {
    if (frame <= keys[i].frame) {
      const a = keys[i - 1], b = keys[i];
      return a.value + (b.value - a.value) * (frame - a.frame) / (b.frame - a.frame);
    }
  }
  return keys[keys.length - 1].value;
}

export function sourceFrameAtOutputTime(outputSeconds, recipe) {
  const fps = Number(recipe.frameRate.numerator) / Number(recipe.frameRate.denominator);
  // WebCodecs timestamps have microsecond precision; compensate less than
  // 0.001 frame so rational rates do not evaluate the preceding opacity key.
  return Math.min(recipe.outFrame - 1, Math.max(recipe.inFrame,
    recipe.inFrame + Math.floor(outputSeconds * fps + 1e-3)));
}

export function validateRecipe(recipe) {
  const fps = Number(recipe.frameRate?.numerator) / Number(recipe.frameRate?.denominator);
  if (recipe.format !== 'neom-video-recipe' || recipe.version !== 1 ||
      !Number.isFinite(fps) || fps < 1 || fps > 240 ||
      !Number.isSafeInteger(recipe.inFrame) || !Number.isSafeInteger(recipe.outFrame) ||
      recipe.inFrame < 0 || recipe.outFrame <= recipe.inFrame ||
      !Array.isArray(recipe.opacityKeys) || recipe.opacityKeys.length > 1000) {
    throw new Error('Receta de vídeo inválida.');
  }
  let previous = -1;
  for (const key of recipe.opacityKeys) {
    if (!Number.isSafeInteger(key.frame) || key.frame <= previous ||
        !Number.isFinite(key.value) || key.value < 0 || key.value > 1) {
      throw new Error('Fotogramas clave de opacidad inválidos.');
    }
    previous = key.frame;
  }
  return { fps, start: recipe.inFrame / fps, end: recipe.outFrame / fps };
}
