#!/usr/bin/env node
// THE SET MUST BE DERIVED, NEVER LISTED. These tests exist so the check cannot rot into a paste.
//
// The nine this tool reports were found by a lane running the same enumeration on two mains an hour
// apart and getting the same answer, which is the only honest way to report a set. The failure mode
// is specific and it is quiet: someone edits the manifest, or adds a harness, and a hardcoded list
// keeps asserting the old number. Nothing goes red, because a list does not know the repository
// changed.
//
// So these tests do not check what the current answer is. They check that the answer is COMPUTED -
// that a manifest edit changes the output, and that a helper is not counted as a harness.
//
// Run: node tools/unregistered-harnesses.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { classify } from "./unregistered-harnesses.mjs";

const MANIFEST = `
const HARNESS_SCRIPTS = [
  ['assets', 'res://addons/cabra.lat_shooters/test/validate_assets.gd'],
  ['stash_view', 'res://addons/cabra.lat_shooters/test/validate_stash_view.gd'],
];
`;
const sceneTree = "extends SceneTree\nfunc _initialize(): pass\n";
const refCounted = "extends RefCounted\nclass_name Util\n";
const read = (map) => (f) => map[f] ?? "";

test("a SceneTree file no row names is reported as unregistered", () => {
  const r = classify(["test/validate_a.gd"], MANIFEST, read({ "test/validate_a.gd": sceneTree }));
  assert.deepEqual(r.unregistered, ["test/validate_a.gd"]);
  assert.deepEqual(r.registered, []);
  assert.deepEqual(r.notHarness, []);
});

test("a non-SceneTree file is excluded rather than counted as a harness", () => {
  // The tenth item. validate_util.gd extends RefCounted and cannot be run, so a glob that ignores
  // `extends` reports ten where the real answer is nine - and the difference would be a decision
  // about the count rather than a fact about the file.
  const r = classify(["src/meta/validate_util.gd"], MANIFEST, read({ "src/meta/validate_util.gd": refCounted }));
  assert.deepEqual(r.unregistered, [], "a helper is not an unrun harness");
  assert.equal(r.notHarness.length, 1);
  assert.equal(r.notHarness[0].ext, "RefCounted");
});

test("a file the manifest names is registered", () => {
  const f = "addons/cabra.lat_shooters/test/validate_stash_view.gd";
  const r = classify([f], MANIFEST, read({ [f]: sceneTree }));
  assert.deepEqual(r.registered, [f]);
  assert.deepEqual(r.unregistered, []);
});

test("the answer is COMPUTED, so a manifest edit changes it - the anti-rot property", () => {
  // This is the whole reason the tool is derived rather than a list. Editing the manifest moves a
  // file between the two sets, and a hardcoded list would not notice.
  const f = "test/validate_b.gd";
  const files = [f];
  const before = classify(files, MANIFEST, read({ [f]: sceneTree }));
  assert.equal(before.unregistered.length, 1);

  const amended = MANIFEST.replace("];", `  ['b', 'res://test/validate_b.gd'],\n];`);
  const after = classify(files, amended, read({ [f]: sceneTree }));
  assert.equal(after.unregistered.length, 0, "registering the harness must move it, with no code change");
  assert.equal(after.registered.length, 1);
});

test("matching is on the full path, so a same-named file elsewhere is not credited", () => {
  // A substring match would let src/meta/validate_stash_view.gd be satisfied by a row naming the
  // addon's copy - the same class as a grep that counts the wrong thing.
  const f = "src/meta/validate_stash_view.gd";
  const r = classify([f], MANIFEST, read({ [f]: sceneTree }));
  assert.deepEqual(r.unregistered, [f], "a different path is a different file");
});
