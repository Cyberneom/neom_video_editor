import test from 'node:test';
import assert from 'node:assert/strict';
import { opacityAtFrame, sourceFrameAtOutputTime, validateRecipe } from './recipe_math.js';
const recipe = { format: 'neom-video-recipe', version: 1, frameRate: { numerator: '24', denominator: '1' }, inFrame: 24, outFrame: 96, opacityKeys: [{ frame: 24, value: 0 }, { frame: 48, value: 1 }, { frame: 72, value: 0 }] };
test('trimmed timestamps still evaluate source keyframes', () => {
  assert.equal(sourceFrameAtOutputTime(0, recipe), 24);
  assert.equal(sourceFrameAtOutputTime(1, recipe), 48);
  assert.equal(opacityAtFrame(recipe.opacityKeys, sourceFrameAtOutputTime(.5, recipe)), .5);
  assert.equal(opacityAtFrame(recipe.opacityKeys, sourceFrameAtOutputTime(2, recipe)), 0);
});
test('rational frame rate and float encoder timestamps land on exact keys', () => {
  const ntsc = { ...recipe, frameRate: { numerator: '30000', denominator: '1001' } };
  assert.equal(sourceFrameAtOutputTime(1001 / 30000 - 1e-9, ntsc), 25);
  assert.equal(sourceFrameAtOutputTime(33366 / 1e6, ntsc), 25);
  assert.equal(sourceFrameAtOutputTime(66733 / 1e6, ntsc), 26);
  assert.equal(sourceFrameAtOutputTime(0, ntsc), 24);
  assert.equal(sourceFrameAtOutputTime(300, ntsc), 95);
});
test('opacity clamps to end keys and empty track has default opacity', () => {
  assert.equal(opacityAtFrame([], 100), 1);
  assert.equal(opacityAtFrame(recipe.opacityKeys, 0), 0);
  assert.equal(opacityAtFrame(recipe.opacityKeys, 120), 0);
});
test('malformed recipes are rejected before opening media', () => {
  assert.deepEqual(validateRecipe(recipe), { fps: 24, start: 1, end: 4 });
  assert.throws(() => validateRecipe({ ...recipe, outFrame: 24 }));
  assert.throws(() => validateRecipe({ ...recipe, opacityKeys: [{ frame: 0, value: NaN }] }));
  assert.throws(() => validateRecipe({ ...recipe, opacityKeys: [{ frame: 1, value: 1 }, { frame: 1, value: 0 }] }));
});
