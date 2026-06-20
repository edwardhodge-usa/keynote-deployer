# Section 05 — Viewer Generator: staged diff

Note: the 4 large .html files (viewer-template.html + 3 fixtures, ~549 lines each of
verbatim-extracted/Electron-generated HTML+minified JS) are EXCLUDED from this diff —
they are machine-generated and byte-identity-verified by generate-fixtures.mjs + tests.
Reviewing: GifViewerGenerator.swift, GifViewerGeneratorTests.swift, generate-fixtures.mjs, project.yml, pbxproj.

```diff
diff --git a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
index deb6c92..c371463 100644
--- a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
+++ b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
@@ -15,6 +15,7 @@
 		3416C3C79989AB5327DF7191 /* GifDeployFoundationTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = D5BACAE5D4399BB77ADCA7B8 /* GifDeployFoundationTests.swift */; };
 		34B729A68FBC01A63C15F608 /* KeynoteDeployerApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = F4F9F98F1120CAF61D82D80B /* KeynoteDeployerApp.swift */; };
 		46171C654C9CF229C03D7615 /* VercelProject.swift in Sources */ = {isa = PBXBuildFile; fileRef = 23F61A6BE61C1CDC6237ADF6 /* VercelProject.swift */; };
+		47A67AFB0EEC39EA960DA268 /* viewer-template.html in Resources */ = {isa = PBXBuildFile; fileRef = 24C4F22DCD456D129607C809 /* viewer-template.html */; };
 		483D3CC267D95282088F9309 /* AppSettings.swift in Sources */ = {isa = PBXBuildFile; fileRef = 28C5E49D1314790083692357 /* AppSettings.swift */; };
 		492021F2C6BA53DA82ADF360 /* VercelDeployer.swift in Sources */ = {isa = PBXBuildFile; fileRef = 282B4D114C60E28D56418FAE /* VercelDeployer.swift */; };
 		4B8F2669D064C5BD83CA4387 /* PipelineResult.swift in Sources */ = {isa = PBXBuildFile; fileRef = 17821C750B379235D1F37C5E /* PipelineResult.swift */; };
@@ -31,13 +32,16 @@
 		84C92D6C1E3FBCD22171220F /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 748C27488D67FC5F775B7ABB /* ContentView.swift */; };
 		93009A0C3460A2193451E298 /* SlideDetector.swift in Sources */ = {isa = PBXBuildFile; fileRef = 80DDA549D53D62032322E1E0 /* SlideDetector.swift */; };
 		9467E10D5FA4765BE26819DF /* DeployProgressView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 252E013E7FB809AC24354D6C /* DeployProgressView.swift */; };
+		9EA72BB2104408A105BFF36A /* GifViewerGenerator.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2102C4D448EED8B168CE086D /* GifViewerGenerator.swift */; };
 		A14416E992CD0B244FFA16A1 /* GridSamplerTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 403D899438A463CD2A362774 /* GridSamplerTests.swift */; };
 		A230A93A825F8EF3B09C1AE8 /* VercelAPI.swift in Sources */ = {isa = PBXBuildFile; fileRef = 17A85902F080898C86352154 /* VercelAPI.swift */; };
+		B39E8C2DDE5D70C31CD97C32 /* viewer-template.html in Resources */ = {isa = PBXBuildFile; fileRef = 24C4F22DCD456D129607C809 /* viewer-template.html */; };
 		BE71A16FFD585CD12AD762B1 /* KeynoteMetadata.swift in Sources */ = {isa = PBXBuildFile; fileRef = CE7E2BD93E4F1F90654BA3E7 /* KeynoteMetadata.swift */; };
 		C1320156DDC609C7483B1F6A /* GridSampler.swift in Sources */ = {isa = PBXBuildFile; fileRef = 38B3998DF7B225F311525034 /* GridSampler.swift */; };
 		C4E54C86FF711C684113EACE /* HistoryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = B55FB9E316B645CFD0C08B4F /* HistoryView.swift */; };
 		E1C3E1D40795A6A0143F56B3 /* GifDeploy.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1DBEB636C2099B4912F4EAF9 /* GifDeploy.swift */; };
 		EA8F1C902A8D2AD7D8A93A30 /* AppConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = 390DDF13A88F1C59BE62D165 /* AppConfig.swift */; };
+		EC188D1E3C861668FEF13F5B /* GifViewerGeneratorTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = EE0C57EBD975ADE41C5038B7 /* GifViewerGeneratorTests.swift */; };
 		F83478250D2F6D1FD03CE852 /* KeynoteProcessor.swift in Sources */ = {isa = PBXBuildFile; fileRef = 987B91A81602E8E224604358 /* KeynoteProcessor.swift */; };
 		FDACB1C1BAB30EF321B1BAA9 /* BoundaryMathTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 861EF8BF58FB1B72E46E7710 /* BoundaryMathTests.swift */; };
 /* End PBXBuildFile section */
@@ -58,7 +62,9 @@
 		17A85902F080898C86352154 /* VercelAPI.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VercelAPI.swift; sourceTree = "<group>"; };
 		1C1AE82499CE26C6968F8AA7 /* UpdaterService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdaterService.swift; sourceTree = "<group>"; };
 		1DBEB636C2099B4912F4EAF9 /* GifDeploy.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GifDeploy.swift; sourceTree = "<group>"; };
+		2102C4D448EED8B168CE086D /* GifViewerGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GifViewerGenerator.swift; sourceTree = "<group>"; };
 		23F61A6BE61C1CDC6237ADF6 /* VercelProject.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VercelProject.swift; sourceTree = "<group>"; };
+		24C4F22DCD456D129607C809 /* viewer-template.html */ = {isa = PBXFileReference; lastKnownFileType = text.html; path = "viewer-template.html"; sourceTree = "<group>"; };
 		25181D8CAB9909769D352295 /* DeploymentVerifier.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeploymentVerifier.swift; sourceTree = "<group>"; };
 		252E013E7FB809AC24354D6C /* DeployProgressView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeployProgressView.swift; sourceTree = "<group>"; };
 		27F54EA164F3AD6A14907287 /* KeynoteDeployer.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = KeynoteDeployer.entitlements; sourceTree = "<group>"; };
@@ -88,6 +94,7 @@
 		D5BACAE5D4399BB77ADCA7B8 /* GifDeployFoundationTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GifDeployFoundationTests.swift; sourceTree = "<group>"; };
 		E3C9945227E19D94B300923C /* SidebarView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SidebarView.swift; sourceTree = "<group>"; };
 		EC7E6FAEC55BC08F00535E8C /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist; path = Info.plist; sourceTree = "<group>"; };
+		EE0C57EBD975ADE41C5038B7 /* GifViewerGeneratorTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GifViewerGeneratorTests.swift; sourceTree = "<group>"; };
 		F23DFAEC2277359D2ECF9D69 /* DeployView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeployView.swift; sourceTree = "<group>"; };
 		F4F9F98F1120CAF61D82D80B /* KeynoteDeployerApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KeynoteDeployerApp.swift; sourceTree = "<group>"; };
 /* End PBXFileReference section */
@@ -110,6 +117,7 @@
 				25181D8CAB9909769D352295 /* DeploymentVerifier.swift */,
 				082147F09FC716A0BEAD8B15 /* FileOperations.swift */,
 				75C0679035D8B881EC65E7BF /* GifFrameSource.swift */,
+				2102C4D448EED8B168CE086D /* GifViewerGenerator.swift */,
 				38B3998DF7B225F311525034 /* GridSampler.swift */,
 				A80FCBDC9C1ECDDA55886B5A /* IndexHtmlGenerator.swift */,
 				987B91A81602E8E224604358 /* KeynoteProcessor.swift */,
@@ -167,18 +175,28 @@
 				F6CE63646D32F7965E61F662 /* App */,
 				F86DB4CB5385252AA5F74EBF /* Config */,
 				7105A5427370184AA6743664 /* Models */,
+				A0DC1E512498B9D6051EE54E /* Resources */,
 				01C679620FE08A5704268729 /* Services */,
 				403E53FCE746D53A87F8756C /* Views */,
 			);
 			path = Sources;
 			sourceTree = "<group>";
 		};
+		A0DC1E512498B9D6051EE54E /* Resources */ = {
+			isa = PBXGroup;
+			children = (
+				24C4F22DCD456D129607C809 /* viewer-template.html */,
+			);
+			path = Resources;
+			sourceTree = "<group>";
+		};
 		CCCD953E78791DE72243A9A3 /* Tests */ = {
 			isa = PBXGroup;
 			children = (
 				861EF8BF58FB1B72E46E7710 /* BoundaryMathTests.swift */,
 				D5BACAE5D4399BB77ADCA7B8 /* GifDeployFoundationTests.swift */,
 				3CD02D196EF4CF931312E5C5 /* GifFrameSourceTests.swift */,
+				EE0C57EBD975ADE41C5038B7 /* GifViewerGeneratorTests.swift */,
 				403D899438A463CD2A362774 /* GridSamplerTests.swift */,
 				4F761BD7A31380F0C3C431BA /* SlideDetectorTests.swift */,
 			);
@@ -228,6 +246,7 @@
 			buildConfigurationList = 2FAD024BC12DC30440F1747A /* Build configuration list for PBXNativeTarget "KeynoteDeployer" */;
 			buildPhases = (
 				A235079C29649013D0782B86 /* Sources */,
+				E066FE53151E7CFCE7565DC8 /* Resources */,
 				711AF864EE7C11D78482A579 /* Frameworks */,
 			);
 			buildRules = (
@@ -247,6 +266,7 @@
 			buildConfigurationList = E67E2BCC4174195367F2867C /* Build configuration list for PBXNativeTarget "KeynoteDeployerTests" */;
 			buildPhases = (
 				205D47036125B10D5F90336F /* Sources */,
+				A3AA064962233BC5149B3C33 /* Resources */,
 			);
 			buildRules = (
 			);
@@ -301,6 +321,25 @@
 		};
 /* End PBXProject section */
 
+/* Begin PBXResourcesBuildPhase section */
+		A3AA064962233BC5149B3C33 /* Resources */ = {
+			isa = PBXResourcesBuildPhase;
+			buildActionMask = 2147483647;
+			files = (
+				B39E8C2DDE5D70C31CD97C32 /* viewer-template.html in Resources */,
+			);
+			runOnlyForDeploymentPostprocessing = 0;
+		};
+		E066FE53151E7CFCE7565DC8 /* Resources */ = {
+			isa = PBXResourcesBuildPhase;
+			buildActionMask = 2147483647;
+			files = (
+				47A67AFB0EEC39EA960DA268 /* viewer-template.html in Resources */,
+			);
+			runOnlyForDeploymentPostprocessing = 0;
+		};
+/* End PBXResourcesBuildPhase section */
+
 /* Begin PBXSourcesBuildPhase section */
 		205D47036125B10D5F90336F /* Sources */ = {
 			isa = PBXSourcesBuildPhase;
@@ -309,6 +348,7 @@
 				FDACB1C1BAB30EF321B1BAA9 /* BoundaryMathTests.swift in Sources */,
 				3416C3C79989AB5327DF7191 /* GifDeployFoundationTests.swift in Sources */,
 				50A06F8202D9B1467A61D76D /* GifFrameSourceTests.swift in Sources */,
+				EC188D1E3C861668FEF13F5B /* GifViewerGeneratorTests.swift in Sources */,
 				A14416E992CD0B244FFA16A1 /* GridSamplerTests.swift in Sources */,
 				25E634C5002EC580E4E03F1B /* SlideDetectorTests.swift in Sources */,
 			);
@@ -327,6 +367,7 @@
 				70CBE64B6030B4BAC00B9F32 /* FileOperations.swift in Sources */,
 				E1C3E1D40795A6A0143F56B3 /* GifDeploy.swift in Sources */,
 				701A3CA56E07018107F78811 /* GifFrameSource.swift in Sources */,
+				9EA72BB2104408A105BFF36A /* GifViewerGenerator.swift in Sources */,
 				C1320156DDC609C7483B1F6A /* GridSampler.swift in Sources */,
 				32E92AFC106BE6E110B3B5BA /* HistoryEntry.swift in Sources */,
 				C4E54C86FF711C684113EACE /* HistoryView.swift in Sources */,
diff --git a/swift-app/Sources/Services/GifViewerGenerator.swift b/swift-app/Sources/Services/GifViewerGenerator.swift
new file mode 100644
index 0000000..997a5c9
--- /dev/null
+++ b/swift-app/Sources/Services/GifViewerGenerator.swift
@@ -0,0 +1,79 @@
+import Foundation
+
+/// Anchor for locating the bundle that ships `viewer-template.html`.
+/// The resource is bundled into BOTH the app target and the test target, so
+/// `Bundle(for:)` resolves to a bundle that contains it regardless of how the
+/// app module is linked into the test runner.
+private final class GifViewerBundleAnchor {}
+
+extension Bundle {
+    /// Bundle that contains `viewer-template.html`.
+    static var gifViewerTemplate: Bundle { Bundle(for: GifViewerBundleAnchor.self) }
+}
+
+/// Stateless generator for the self-contained GIF slide-viewer HTML page.
+///
+/// Phase 1: slide boundaries are baked at deploy time (`BAKED_SLIDES`); the
+/// deployed viewer never detects slides itself — it just navigates the baked list.
+///
+/// WARNING — XSS / injection: never inject raw, unescaped user-provided strings
+/// into the template. The ONLY injected values are a JSON array of integers
+/// (`{{BAKED_SLIDES}}`), a filename (`{{GIF_FILENAME}}`), and two bool-driven
+/// secure-embed snippets. `title` / `projectName` from `GifDeployRequest` are
+/// DELIBERATELY NOT injected — doing so would be an XSS vector in the deployed
+/// (public) viewer. Keep it that way.
+enum GifViewerGenerator {
+    /// Secure-embed CSS — copied verbatim from `electron/gifViewerGenerator.ts`.
+    private static let secureEmbedCss = "body { user-select: none; } canvas { pointer-events: none; }"
+    /// Secure-embed script — copied verbatim from `electron/gifViewerGenerator.ts`.
+    private static let secureEmbedScript = "document.addEventListener('contextmenu', function(e) { e.preventDefault(); });"
+
+    /// Emit the self-contained viewer HTML for the given GIF + baked slides.
+    ///
+    /// Output MUST be byte-identical to the Electron `generateGifViewerHtml(...)`
+    /// for the same inputs (GATE-1). The template is `viewer-template.html`,
+    /// extracted verbatim from the Electron generator with four placeholders.
+    static func generate(
+        gifFilename: String,
+        secureEmbed: Bool,
+        slides: [DetectedSlide],
+        bundle: Bundle = .gifViewerTemplate
+    ) -> String {
+        guard let url = bundle.url(forResource: "viewer-template", withExtension: "html"),
+              let template = try? String(contentsOf: url, encoding: .utf8) else {
+            // Packaging error — the resource is build-time guaranteed (declared in project.yml).
+            fatalError("viewer-template.html not found in bundle: \(bundle.bundlePath)")
+        }
+
+        return template
+            .replacingOccurrences(of: "{{GIF_FILENAME}}", with: gifFilename)
+            .replacingOccurrences(of: "{{BAKED_SLIDES}}", with: bakedSlidesJSON(slides))
+            .replacingOccurrences(of: "{{SECURE_EMBED_CSS}}", with: secureEmbed ? secureEmbedCss : "")
+            .replacingOccurrences(of: "{{SECURE_EMBED_SCRIPT}}", with: secureEmbed ? secureEmbedScript : "")
+    }
+
+    /// Build the `BAKED_SLIDES` value to match JavaScript `JSON.stringify(slides)`
+    /// BYTE-FOR-BYTE: compact (no whitespace), insertion-order keys
+    /// (restFrame, holdStart, holdEnd, transitionFrames), nested order (start, end),
+    /// lowercase `null` for an absent transition, `[]` for empty.
+    ///
+    /// Hand-assembled deliberately: `DetectedSlide` has ZERO string fields, so
+    /// there is no escaping hazard and key order is guaranteed.
+    ///
+    /// FORWARD-GUARD: if a string field is ever added to `DetectedSlide`, switch
+    /// to a parity-preserving encoder that escapes strings while preserving the
+    /// `JSON.stringify` key order — NEVER `JSONEncoder.OutputFormatting.sortedKeys`
+    /// (sorted keys = alphabetical = breaks the byte-identical viewer gate).
+    private static func bakedSlidesJSON(_ slides: [DetectedSlide]) -> String {
+        let items = slides.map { s -> String in
+            let tf: String
+            if let t = s.transitionFrames {
+                tf = "{\"start\":\(t.start),\"end\":\(t.end)}"
+            } else {
+                tf = "null"
+            }
+            return "{\"restFrame\":\(s.restFrame),\"holdStart\":\(s.holdStart),\"holdEnd\":\(s.holdEnd),\"transitionFrames\":\(tf)}"
+        }
+        return "[" + items.joined(separator: ",") + "]"
+    }
+}
diff --git a/swift-app/Tests/Fixtures/generate-fixtures.mjs b/swift-app/Tests/Fixtures/generate-fixtures.mjs
new file mode 100644
index 0000000..e8fd6fa
--- /dev/null
+++ b/swift-app/Tests/Fixtures/generate-fixtures.mjs
@@ -0,0 +1,107 @@
+// Generates the byte-identical fixtures + the viewer-template.html for the Swift
+// GifViewerGenerator port (section-05). Run from repo root:
+//   node swift-app/Tests/Fixtures/generate-fixtures.mjs
+//
+// HOW IT GUARANTEES BYTE-IDENTITY:
+//  - Fixtures are the literal output of the REAL Electron generateGifViewerHtml(...).
+//  - The template is derived from a real render with unique SENTINEL inputs, then
+//    those sentinels are reverse-substituted back to {{PLACEHOLDERS}}. So the
+//    template's static text is, by construction, Electron's output verbatim.
+import { build } from 'esbuild'
+import { fileURLToPath, pathToFileURL } from 'node:url'
+import { dirname, join } from 'node:path'
+import { writeFileSync, mkdirSync, rmSync } from 'node:fs'
+
+const here = dirname(fileURLToPath(import.meta.url))
+const repoRoot = join(here, '..', '..', '..')
+const tsSource = join(repoRoot, 'electron', 'gifViewerGenerator.ts')
+
+// Transpile the self-contained TS generator to a temp ESM module and import it.
+const tmpModule = join(here, '.__gen_tmp.mjs')
+await build({
+  entryPoints: [tsSource],
+  bundle: true,
+  format: 'esm',
+  platform: 'node',
+  outfile: tmpModule,
+  logLevel: 'silent',
+})
+const { generateGifViewerHtml } = await import(pathToFileURL(tmpModule).href)
+rmSync(tmpModule, { force: true })
+
+// ── Fixtures (these inputs MUST match GifViewerGeneratorTests.swift) ──
+const SLIDES = [
+  { restFrame: 10, holdStart: 8, holdEnd: 14, transitionFrames: { start: 15, end: 18 } },
+  { restFrame: 30, holdStart: 28, holdEnd: 34, transitionFrames: null },
+]
+
+mkdirSync(here, { recursive: true })
+const write = (name, content) => {
+  writeFileSync(join(here, name), content)
+  console.log(`wrote ${name} (${content.length} bytes)`)
+}
+
+write('viewer-secure-true.html', generateGifViewerHtml('deck.gif', true, SLIDES))
+write('viewer-secure-false.html', generateGifViewerHtml('deck.gif', false, SLIDES))
+write('viewer-empty-slides.html', generateGifViewerHtml('deck.gif', false, []))
+
+// ── Template extraction via reverse-substitution ──
+const GIF_SENTINEL = '__KDPLH_GIF_SENTINEL__'
+const SLIDES_SENTINEL = [{ restFrame: 987654321, holdStart: 0, holdEnd: 0, transitionFrames: null }]
+const SLIDES_SENTINEL_JSON = JSON.stringify(SLIDES_SENTINEL)
+const SECURE_CSS = 'body { user-select: none; } canvas { pointer-events: none; }'
+const SECURE_SCRIPT = "document.addEventListener('contextmenu', function(e) { e.preventDefault(); });"
+
+// secure=true so BOTH secure strings are present and replaceable.
+let tpl = generateGifViewerHtml(GIF_SENTINEL, true, SLIDES_SENTINEL)
+
+const assertOne = (haystack, needle, label) => {
+  const n = haystack.split(needle).length - 1
+  if (n !== 1) throw new Error(`Expected exactly 1 occurrence of ${label}, found ${n}`)
+}
+assertOne(tpl, GIF_SENTINEL, 'GIF sentinel')
+assertOne(tpl, SLIDES_SENTINEL_JSON, 'slides sentinel JSON')
+assertOne(tpl, SECURE_CSS, 'secure CSS')
+assertOne(tpl, SECURE_SCRIPT, 'secure script')
+
+tpl = tpl
+  .replace(GIF_SENTINEL, '{{GIF_FILENAME}}')
+  .replace(SLIDES_SENTINEL_JSON, '{{BAKED_SLIDES}}')
+  .replace(SECURE_CSS, '{{SECURE_EMBED_CSS}}')
+  .replace(SECURE_SCRIPT, '{{SECURE_EMBED_SCRIPT}}')
+
+// Template must contain exactly the 4 placeholders and no stray sentinels.
+for (const ph of ['{{GIF_FILENAME}}', '{{BAKED_SLIDES}}', '{{SECURE_EMBED_CSS}}', '{{SECURE_EMBED_SCRIPT}}']) {
+  assertOne(tpl, ph, ph)
+}
+
+const resourcesDir = join(repoRoot, 'swift-app', 'Sources', 'Resources')
+mkdirSync(resourcesDir, { recursive: true })
+writeFileSync(join(resourcesDir, 'viewer-template.html'), tpl)
+console.log(`wrote Sources/Resources/viewer-template.html (${tpl.length} bytes)`)
+
+// ── Self-check: forward-render the template (mirroring Swift logic) == fixtures ──
+const render = (gif, secure, slides) =>
+  tpl
+    .replaceAll('{{GIF_FILENAME}}', gif)
+    .replaceAll('{{BAKED_SLIDES}}', JSON.stringify(slides))
+    .replaceAll('{{SECURE_EMBED_CSS}}', secure ? SECURE_CSS : '')
+    .replaceAll('{{SECURE_EMBED_SCRIPT}}', secure ? SECURE_SCRIPT : '')
+
+const check = (name, gif, secure, slides) => {
+  const expected = generateGifViewerHtml(gif, secure, slides)
+  const got = render(gif, secure, slides)
+  if (got !== expected) {
+    for (let i = 0; i < Math.max(got.length, expected.length); i++) {
+      if (got[i] !== expected[i]) {
+        throw new Error(`${name}: template render diverges at index ${i}: got ${JSON.stringify(got.slice(i, i + 40))} vs ${JSON.stringify(expected.slice(i, i + 40))}`)
+      }
+    }
+    throw new Error(`${name}: length mismatch ${got.length} vs ${expected.length}`)
+  }
+  console.log(`self-check OK: ${name}`)
+}
+check('secure-true', 'deck.gif', true, SLIDES)
+check('secure-false', 'deck.gif', false, SLIDES)
+check('empty-slides', 'deck.gif', false, [])
+console.log('ALL GOOD — template reproduces Electron output byte-for-byte.')
diff --git a/swift-app/Tests/GifViewerGeneratorTests.swift b/swift-app/Tests/GifViewerGeneratorTests.swift
new file mode 100644
index 0000000..47c88c0
--- /dev/null
+++ b/swift-app/Tests/GifViewerGeneratorTests.swift
@@ -0,0 +1,103 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+/// GATE-1: GifViewerGenerator output must be byte-identical to the Electron
+/// `generateGifViewerHtml(...)`. Fixtures live next to this file under Fixtures/
+/// and are the literal output of the real Electron generator (regenerate with
+/// `node swift-app/Tests/Fixtures/generate-fixtures.mjs`).
+@Suite("GifViewerGenerator")
+struct GifViewerGeneratorTests {
+
+    // The fixture `slides` array MUST match generate-fixtures.mjs exactly.
+    static let slides: [DetectedSlide] = [
+        DetectedSlide(restFrame: 10, holdStart: 8, holdEnd: 14, transitionFrames: TransitionRange(start: 15, end: 18)),
+        DetectedSlide(restFrame: 30, holdStart: 28, holdEnd: 34, transitionFrames: nil),
+    ]
+
+    /// Read a committed Electron fixture from the source tree (via #filePath —
+    /// no bundling needed; the source is present locally and in CI).
+    static func fixture(_ name: String) throws -> String {
+        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
+        let url = dir.appendingPathComponent(name)
+        return try String(contentsOf: url, encoding: .utf8)
+    }
+
+    // MARK: - Template-asset integrity (Task 5)
+
+    @Test("No stray {{...}} placeholders remain after substitution")
+    func noStrayPlaceholders() {
+        let out = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: true, slides: Self.slides)
+        // `{{` is unique to template placeholders (the inlined minified JS uses `}}`
+        // in its own syntax, so only the opening `{{` is a reliable stray-marker).
+        #expect(!out.contains("{{"))
+        for token in ["{{GIF_FILENAME}}", "{{BAKED_SLIDES}}", "{{SECURE_EMBED_CSS}}", "{{SECURE_EMBED_SCRIPT}}"] {
+            #expect(!out.contains(token))
+        }
+    }
+
+    // MARK: - Byte-identical gate (Task 6, GATE-1)
+
+    @Test("secure=true output is byte-identical to Electron fixture")
+    func byteIdenticalSecureTrue() throws {
+        let out = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: true, slides: Self.slides)
+        let expected = try Self.fixture("viewer-secure-true.html")
+        #expect(out == expected)
+    }
+
+    @Test("secure=false output is byte-identical to Electron fixture")
+    func byteIdenticalSecureFalse() throws {
+        let out = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: false, slides: Self.slides)
+        let expected = try Self.fixture("viewer-secure-false.html")
+        #expect(out == expected)
+    }
+
+    @Test("empty slides produce a well-formed page matching the fixture")
+    func byteIdenticalEmptySlides() throws {
+        let out = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: false, slides: [])
+        let expected = try Self.fixture("viewer-empty-slides.html")
+        #expect(out == expected)
+        #expect(out.contains("var BAKED_SLIDES = [];"))
+    }
+
+    // MARK: - JSON parity (Task 6)
+
+    @Test("baked slides JSON matches JSON.stringify byte-for-byte (insertion order, null, nested order)")
+    func bakedSlidesJSONParity() {
+        let out = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: false, slides: Self.slides)
+        let expectedJSON = #"[{"restFrame":10,"holdStart":8,"holdEnd":14,"transitionFrames":{"start":15,"end":18}},{"restFrame":30,"holdStart":28,"holdEnd":34,"transitionFrames":null}]"#
+        #expect(out.contains("var BAKED_SLIDES = \(expectedJSON);"))
+    }
+
+    @Test("baked slides JSON is NOT alphabetical (guards against .sortedKeys regression)")
+    func bakedSlidesNotAlphabetical() {
+        let out = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: false, slides: Self.slides)
+        // restFrame must precede holdStart; output must not start a slide object with "holdEnd".
+        let restIdx = try! #require(out.range(of: "\"restFrame\":10"))
+        let holdStartIdx = try! #require(out.range(of: "\"holdStart\":8"))
+        #expect(restIdx.lowerBound < holdStartIdx.lowerBound)
+        #expect(!out.contains(#"{"holdEnd""#))
+    }
+
+    // MARK: - Secure-embed toggle (Task 6)
+
+    @Test("secure=true contains both secure snippets; secure=false contains neither")
+    func secureEmbedToggle() {
+        let secure = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: true, slides: Self.slides)
+        let insecure = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: false, slides: Self.slides)
+
+        #expect(secure.contains("body { user-select: none; }"))
+        #expect(secure.contains("e.preventDefault()"))
+
+        #expect(!insecure.contains("body { user-select: none; }"))
+        #expect(!insecure.contains("e.preventDefault()"))
+    }
+
+    // MARK: - GIF filename injection
+
+    @Test("gifFilename is injected into the fetch call")
+    func gifFilenameInjected() {
+        let out = GifViewerGenerator.generate(gifFilename: "my-deck.gif", secureEmbed: false, slides: Self.slides)
+        #expect(out.contains("fetch('./my-deck.gif')"))
+    }
+}
diff --git a/swift-app/project.yml b/swift-app/project.yml
index 6a30c71..a15d703 100644
--- a/swift-app/project.yml
+++ b/swift-app/project.yml
@@ -64,6 +64,9 @@ targets:
     platform: macOS
     sources:
       - path: Tests
+        excludes:
+          - "Fixtures/**"   # fixtures read via #filePath; not bundled
+      - path: Sources/Resources   # bundle viewer-template.html into the test bundle too
     dependencies:
       - target: KeynoteDeployer
     settings:
```
