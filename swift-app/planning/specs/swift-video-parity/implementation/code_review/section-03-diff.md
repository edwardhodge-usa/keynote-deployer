diff --git a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
index ed0e318..86798fb 100644
--- a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
+++ b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
@@ -10,6 +10,7 @@
 		07A8FA865923A9F4F325A61A /* StillsMatch.swift in Sources */ = {isa = PBXBuildFile; fileRef = D57C9F761A616991B1231F01 /* StillsMatch.swift */; };
 		13F48A1926D584294516EEE0 /* SidebarView.swift in Sources */ = {isa = PBXBuildFile; fileRef = E3C9945227E19D94B300923C /* SidebarView.swift */; };
 		15125B060EAC0C268F273761 /* ProjectsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A857D151061C711E9B9957C8 /* ProjectsView.swift */; };
+		22CAA3C6B137E1DD00364127 /* video-viewer-golden-plain.html in Resources */ = {isa = PBXBuildFile; fileRef = 0A7E4D56A5BFA32DA7B9285F /* video-viewer-golden-plain.html */; };
 		2D5BD33951D0A7FF662C0A3F /* IndexHtmlGenerator.swift in Sources */ = {isa = PBXBuildFile; fileRef = A80FCBDC9C1ECDDA55886B5A /* IndexHtmlGenerator.swift */; };
 		32E92AFC106BE6E110B3B5BA /* HistoryEntry.swift in Sources */ = {isa = PBXBuildFile; fileRef = 6014F6E3BFFA0FEA826D475F /* HistoryEntry.swift */; };
 		34B729A68FBC01A63C15F608 /* KeynoteDeployerApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = F4F9F98F1120CAF61D82D80B /* KeynoteDeployerApp.swift */; };
@@ -17,6 +18,7 @@
 		46171C654C9CF229C03D7615 /* VercelProject.swift in Sources */ = {isa = PBXBuildFile; fileRef = 23F61A6BE61C1CDC6237ADF6 /* VercelProject.swift */; };
 		483D3CC267D95282088F9309 /* AppSettings.swift in Sources */ = {isa = PBXBuildFile; fileRef = 28C5E49D1314790083692357 /* AppSettings.swift */; };
 		492021F2C6BA53DA82ADF360 /* VercelDeployer.swift in Sources */ = {isa = PBXBuildFile; fileRef = 282B4D114C60E28D56418FAE /* VercelDeployer.swift */; };
+		4A2E1C7FE7EE01DC8EB9F111 /* VideoViewerGenerator.swift in Sources */ = {isa = PBXBuildFile; fileRef = 42ABCE72BEC351859554D951 /* VideoViewerGenerator.swift */; };
 		4B289C6795B7E64A9625F96D /* StillsMatchTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = E0A6C88075BDCE7E6E5AF0C9 /* StillsMatchTests.swift */; };
 		4B8F2669D064C5BD83CA4387 /* PipelineResult.swift in Sources */ = {isa = PBXBuildFile; fileRef = 17821C750B379235D1F37C5E /* PipelineResult.swift */; };
 		4C00428279F6EAE4F1216066 /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = DF36B5B1F47AEAEE2E972A00 /* Sparkle */; };
@@ -24,6 +26,7 @@
 		54EA0EA3D9BD76F228023924 /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 4A3AD033AAD0411C7CA1B6CD /* SettingsView.swift */; };
 		68FCF5155F11F63CBB34761F /* DeploymentVerifier.swift in Sources */ = {isa = PBXBuildFile; fileRef = 25181D8CAB9909769D352295 /* DeploymentVerifier.swift */; };
 		70CBE64B6030B4BAC00B9F32 /* FileOperations.swift in Sources */ = {isa = PBXBuildFile; fileRef = 082147F09FC716A0BEAD8B15 /* FileOperations.swift */; };
+		77788CDBF10422EED9C391D2 /* video-viewer-template.html in Resources */ = {isa = PBXBuildFile; fileRef = 0C46C9CD46B3D1C3098570B6 /* video-viewer-template.html */; };
 		7DAEEC6461E2EA43B6189CBE /* UpdaterService.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1C1AE82499CE26C6968F8AA7 /* UpdaterService.swift */; };
 		7EE6E590CE33B1217355E8BE /* ProcessingStep.swift in Sources */ = {isa = PBXBuildFile; fileRef = 6E9CE1B85FB4D719BE7B0EC8 /* ProcessingStep.swift */; };
 		84AF2E114BF9B992367626D4 /* DeployView.swift in Sources */ = {isa = PBXBuildFile; fileRef = F23DFAEC2277359D2ECF9D69 /* DeployView.swift */; };
@@ -32,9 +35,11 @@
 		9467E10D5FA4765BE26819DF /* DeployProgressView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 252E013E7FB809AC24354D6C /* DeployProgressView.swift */; };
 		A14416E992CD0B244FFA16A1 /* GridSamplerTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 403D899438A463CD2A362774 /* GridSamplerTests.swift */; };
 		A230A93A825F8EF3B09C1AE8 /* VercelAPI.swift in Sources */ = {isa = PBXBuildFile; fileRef = 17A85902F080898C86352154 /* VercelAPI.swift */; };
+		A7B6DA5811520FD9E09E749F /* video-viewer-golden-secure.html in Resources */ = {isa = PBXBuildFile; fileRef = 61E0452AB31EE55316A70A2D /* video-viewer-golden-secure.html */; };
 		BE71A16FFD585CD12AD762B1 /* KeynoteMetadata.swift in Sources */ = {isa = PBXBuildFile; fileRef = CE7E2BD93E4F1F90654BA3E7 /* KeynoteMetadata.swift */; };
 		C1320156DDC609C7483B1F6A /* GridSampler.swift in Sources */ = {isa = PBXBuildFile; fileRef = 38B3998DF7B225F311525034 /* GridSampler.swift */; };
 		C4E54C86FF711C684113EACE /* HistoryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = B55FB9E316B645CFD0C08B4F /* HistoryView.swift */; };
+		CF38C9DBAC8AFF2AF62781ED /* VideoViewerGeneratorTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B13D91BAAE5426D7EB676719 /* VideoViewerGeneratorTests.swift */; };
 		D11E662E9329C958E5FD05BE /* VideoDeployRequest.swift in Sources */ = {isa = PBXBuildFile; fileRef = CBCFD1B404C9D887FD5FA7B0 /* VideoDeployRequest.swift */; };
 		EA8F1C902A8D2AD7D8A93A30 /* AppConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = 390DDF13A88F1C59BE62D165 /* AppConfig.swift */; };
 		F83478250D2F6D1FD03CE852 /* KeynoteProcessor.swift in Sources */ = {isa = PBXBuildFile; fileRef = 987B91A81602E8E224604358 /* KeynoteProcessor.swift */; };
@@ -52,6 +57,8 @@
 
 /* Begin PBXFileReference section */
 		082147F09FC716A0BEAD8B15 /* FileOperations.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileOperations.swift; sourceTree = "<group>"; };
+		0A7E4D56A5BFA32DA7B9285F /* video-viewer-golden-plain.html */ = {isa = PBXFileReference; lastKnownFileType = text.html; path = "video-viewer-golden-plain.html"; sourceTree = "<group>"; };
+		0C46C9CD46B3D1C3098570B6 /* video-viewer-template.html */ = {isa = PBXFileReference; lastKnownFileType = text.html; path = "video-viewer-template.html"; sourceTree = "<group>"; };
 		17821C750B379235D1F37C5E /* PipelineResult.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PipelineResult.swift; sourceTree = "<group>"; };
 		17A85902F080898C86352154 /* VercelAPI.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VercelAPI.swift; sourceTree = "<group>"; };
 		1C1AE82499CE26C6968F8AA7 /* UpdaterService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdaterService.swift; sourceTree = "<group>"; };
@@ -64,10 +71,12 @@
 		38B3998DF7B225F311525034 /* GridSampler.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GridSampler.swift; sourceTree = "<group>"; };
 		390DDF13A88F1C59BE62D165 /* AppConfig.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppConfig.swift; sourceTree = "<group>"; };
 		403D899438A463CD2A362774 /* GridSamplerTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GridSamplerTests.swift; sourceTree = "<group>"; };
+		42ABCE72BEC351859554D951 /* VideoViewerGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoViewerGenerator.swift; sourceTree = "<group>"; };
 		4A3AD033AAD0411C7CA1B6CD /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
 		537673A9D5C3A3390918F7BE /* .gitkeep */ = {isa = PBXFileReference; path = .gitkeep; sourceTree = "<group>"; };
 		5D3403EAA4D97975ADF59927 /* VideoAnalysis.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoAnalysis.swift; sourceTree = "<group>"; };
 		6014F6E3BFFA0FEA826D475F /* HistoryEntry.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HistoryEntry.swift; sourceTree = "<group>"; };
+		61E0452AB31EE55316A70A2D /* video-viewer-golden-secure.html */ = {isa = PBXFileReference; lastKnownFileType = text.html; path = "video-viewer-golden-secure.html"; sourceTree = "<group>"; };
 		643B10849DA333A7037B54A5 /* KeynoteDeployer.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = KeynoteDeployer.app; sourceTree = BUILT_PRODUCTS_DIR; };
 		66C0C927B53D57B936E42EA7 /* Sparkle.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Sparkle.xcconfig; sourceTree = "<group>"; };
 		6E9CE1B85FB4D719BE7B0EC8 /* ProcessingStep.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProcessingStep.swift; sourceTree = "<group>"; };
@@ -78,6 +87,7 @@
 		A80FCBDC9C1ECDDA55886B5A /* IndexHtmlGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IndexHtmlGenerator.swift; sourceTree = "<group>"; };
 		A857D151061C711E9B9957C8 /* ProjectsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProjectsView.swift; sourceTree = "<group>"; };
 		AA065551FEEAB39DDEAC9B60 /* ModelsAndProjectTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ModelsAndProjectTests.swift; sourceTree = "<group>"; };
+		B13D91BAAE5426D7EB676719 /* VideoViewerGeneratorTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoViewerGeneratorTests.swift; sourceTree = "<group>"; };
 		B55FB9E316B645CFD0C08B4F /* HistoryView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HistoryView.swift; sourceTree = "<group>"; };
 		CBCFD1B404C9D887FD5FA7B0 /* VideoDeployRequest.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoDeployRequest.swift; sourceTree = "<group>"; };
 		CE7E2BD93E4F1F90654BA3E7 /* KeynoteMetadata.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KeynoteMetadata.swift; sourceTree = "<group>"; };
@@ -113,6 +123,7 @@
 				1C1AE82499CE26C6968F8AA7 /* UpdaterService.swift */,
 				17A85902F080898C86352154 /* VercelAPI.swift */,
 				282B4D114C60E28D56418FAE /* VercelDeployer.swift */,
+				42ABCE72BEC351859554D951 /* VideoViewerGenerator.swift */,
 			);
 			path = Services;
 			sourceTree = "<group>";
@@ -171,10 +182,20 @@
 			path = Sources;
 			sourceTree = "<group>";
 		};
+		94CAE77E1E83C3297FBB1B45 /* Fixtures */ = {
+			isa = PBXGroup;
+			children = (
+				0A7E4D56A5BFA32DA7B9285F /* video-viewer-golden-plain.html */,
+				61E0452AB31EE55316A70A2D /* video-viewer-golden-secure.html */,
+			);
+			path = Fixtures;
+			sourceTree = "<group>";
+		};
 		A0DC1E512498B9D6051EE54E /* Resources */ = {
 			isa = PBXGroup;
 			children = (
 				537673A9D5C3A3390918F7BE /* .gitkeep */,
+				0C46C9CD46B3D1C3098570B6 /* video-viewer-template.html */,
 			);
 			path = Resources;
 			sourceTree = "<group>";
@@ -185,6 +206,8 @@
 				403D899438A463CD2A362774 /* GridSamplerTests.swift */,
 				AA065551FEEAB39DDEAC9B60 /* ModelsAndProjectTests.swift */,
 				E0A6C88075BDCE7E6E5AF0C9 /* StillsMatchTests.swift */,
+				B13D91BAAE5426D7EB676719 /* VideoViewerGeneratorTests.swift */,
+				94CAE77E1E83C3297FBB1B45 /* Fixtures */,
 			);
 			path = Tests;
 			sourceTree = "<group>";
@@ -232,6 +255,7 @@
 			buildConfigurationList = 2FAD024BC12DC30440F1747A /* Build configuration list for PBXNativeTarget "KeynoteDeployer" */;
 			buildPhases = (
 				A235079C29649013D0782B86 /* Sources */,
+				E066FE53151E7CFCE7565DC8 /* Resources */,
 				711AF864EE7C11D78482A579 /* Frameworks */,
 			);
 			buildRules = (
@@ -251,6 +275,7 @@
 			buildConfigurationList = E67E2BCC4174195367F2867C /* Build configuration list for PBXNativeTarget "KeynoteDeployerTests" */;
 			buildPhases = (
 				205D47036125B10D5F90336F /* Sources */,
+				A3AA064962233BC5149B3C33 /* Resources */,
 			);
 			buildRules = (
 			);
@@ -305,6 +330,26 @@
 		};
 /* End PBXProject section */
 
+/* Begin PBXResourcesBuildPhase section */
+		A3AA064962233BC5149B3C33 /* Resources */ = {
+			isa = PBXResourcesBuildPhase;
+			buildActionMask = 2147483647;
+			files = (
+				22CAA3C6B137E1DD00364127 /* video-viewer-golden-plain.html in Resources */,
+				A7B6DA5811520FD9E09E749F /* video-viewer-golden-secure.html in Resources */,
+			);
+			runOnlyForDeploymentPostprocessing = 0;
+		};
+		E066FE53151E7CFCE7565DC8 /* Resources */ = {
+			isa = PBXResourcesBuildPhase;
+			buildActionMask = 2147483647;
+			files = (
+				77788CDBF10422EED9C391D2 /* video-viewer-template.html in Resources */,
+			);
+			runOnlyForDeploymentPostprocessing = 0;
+		};
+/* End PBXResourcesBuildPhase section */
+
 /* Begin PBXSourcesBuildPhase section */
 		205D47036125B10D5F90336F /* Sources */ = {
 			isa = PBXSourcesBuildPhase;
@@ -313,6 +358,7 @@
 				A14416E992CD0B244FFA16A1 /* GridSamplerTests.swift in Sources */,
 				419F05D5433E94752E999ED6 /* ModelsAndProjectTests.swift in Sources */,
 				4B289C6795B7E64A9625F96D /* StillsMatchTests.swift in Sources */,
+				CF38C9DBAC8AFF2AF62781ED /* VideoViewerGeneratorTests.swift in Sources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
 		};
@@ -347,6 +393,7 @@
 				46171C654C9CF229C03D7615 /* VercelProject.swift in Sources */,
 				8D642D0B7DE7423F33970CAC /* VideoAnalysis.swift in Sources */,
 				D11E662E9329C958E5FD05BE /* VideoDeployRequest.swift in Sources */,
+				4A2E1C7FE7EE01DC8EB9F111 /* VideoViewerGenerator.swift in Sources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
 		};
diff --git a/swift-app/Sources/Resources/video-viewer-template.html b/swift-app/Sources/Resources/video-viewer-template.html
new file mode 100644
index 0000000..9152b49
--- /dev/null
+++ b/swift-app/Sources/Resources/video-viewer-template.html
@@ -0,0 +1,139 @@
+<!DOCTYPE html>
+<html lang="en"><head>
+<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
+<title>Keynote Slide Viewer</title>
+<style>
+  * { margin:0; padding:0; box-sizing:border-box; }
+  body { background:#0a0a0a; color:#e5e5e5; font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif; min-height:100vh; display:flex; flex-direction:column; align-items:center; }
+  header { width:100%; background:#111; border-bottom:1px solid #222; padding:14px 24px; text-align:center; } header h1 { font-size:16px; font-weight:600; }
+  #deckContainer { display:none; width:100%; max-width:{{VW}}px; margin:24px auto 0; padding:0 16px; }
+  #deck { position:relative; width:100%; aspect-ratio:{{VW}}/{{VH}}; background:#111; border:1px solid #222; border-radius:8px; overflow:hidden; }
+  #deck video { position:absolute; inset:0; width:100%; height:100%; object-fit:contain; display:block; background:#0a0a0a; }
+  #viewer { display:none; width:100%; max-width:{{VW}}px; margin:16px auto 0; padding:0 16px 32px; flex-direction:column; align-items:center; gap:12px; }
+  .controls-row { display:flex; align-items:center; gap:16px; }
+  #slideCounter { font-size:13px; color:#999; min-width:80px; text-align:center; }
+  #dotStrip { display:flex; align-items:center; justify-content:center; flex-wrap:wrap; gap:0; max-width:100%; padding:4px 0; }
+  .dot { width:8px; height:8px; border-radius:50%; background:#333; border:none; padding:0; margin:0 2px; cursor:pointer; min-width:8px; transition:background .1s; } .dot.active{background:#3b82f6;} .dot:hover{background:#555;}
+  button { padding:8px 16px; background:#222; border:1px solid #333; border-radius:6px; color:#ccc; font-size:13px; cursor:pointer; } button:hover{background:#333;} button:disabled{opacity:.3;cursor:default;}
+  .keyboard-hint { font-size:11px; color:#555; }
+  #spinner { width:14px; height:14px; border:2px solid #333; border-top-color:#3b82f6; border-radius:50%; display:none; flex:0 0 auto; }
+  body.busy #spinner { display:inline-block; animation:kd-spin .7s linear infinite; }
+  @keyframes kd-spin { to { transform:rotate(360deg); } }
+  body.in-iframe #spinner { width:clamp(14px,1.5vw,20px); height:clamp(14px,1.5vw,20px); }
+  #loading { display:flex; position:fixed; inset:0; background:rgba(10,10,10,.92); z-index:100; flex-direction:column; align-items:center; justify-content:center; gap:16px; } #loadingText{font-size:14px;color:#999;}
+  #loadSpinner { width:40px; height:40px; border:3px solid rgba(255,255,255,.12); border-top-color:#3b82f6; border-radius:50%; animation:kd-spin .8s linear infinite; }
+  body.viewer-ready #deckContainer { display:block; }
+  @media all {
+    body.in-iframe header, body.in-iframe .keyboard-hint, body.in-iframe .powered-by { display:none !important; }
+    body.in-iframe { height:100vh; overflow:hidden; justify-content:safe center; gap:14px; padding:12px 0; background:transparent; }
+    body.in-iframe.viewer-ready #deckContainer { display:flex; align-items:center; justify-content:center; flex:1 1 auto; min-height:0; max-width:none; width:100%; margin:0; padding:0 16px; }
+    body.in-iframe #deck { width:auto; height:100%; max-width:100%; aspect-ratio:{{VW}}/{{VH}}; background:transparent; border:none; border-radius:0; }
+    body.in-iframe #deck video { background:transparent; }
+    body.in-iframe #viewer { flex:0 0 auto; max-width:none; width:100%; margin:0; padding:0 16px; }
+    body.in-iframe .controls-row { gap:clamp(16px,1.8vw,28px); }
+    body.in-iframe .controls-row button { font-size:clamp(13px,1.4vw,17px); padding:clamp(8px,.9vw,12px) clamp(16px,1.8vw,24px); border-radius:clamp(6px,.6vw,9px); }
+    body.in-iframe #slideCounter { font-size:clamp(13px,1.4vw,17px); min-width:clamp(80px,8vw,110px); }
+    body.in-iframe .dot { width:clamp(8px,.9vw,11px); height:clamp(8px,.9vw,11px); min-width:clamp(8px,.9vw,11px); margin:0 clamp(2px,.25vw,4px); }
+    body.in-iframe #dotStrip { row-gap:6px; }
+    body.in-iframe #loading { background:transparent; } body.in-iframe #loadingText { background:rgba(10,10,10,.82); padding:8px 16px; border-radius:8px; backdrop-filter:blur(4px); }
+  }
+  /* Narrow embeds (phones): the dots wrap into rows and waste height + are too
+     small to tap — drop them, keep Prev/Next + the "X of N" counter. */
+  @media (max-width:549px){ #dotStrip { display:none !important; } }
+  {{SECURE_EMBED_CSS}}
+</style></head>
+<body>
+  <header><h1>Keynote Slide Viewer</h1></header>
+  <div id="deckContainer"><div id="deck"><video id="vid" muted playsinline preload="auto" src="./{{VIDEO_FILENAME}}"></video></div></div>
+  <div id="viewer">
+    <div class="controls-row"><button id="prevBtn" disabled>&#9664; Previous</button><span id="slideCounter">Slide 0 / 0</span><button id="nextBtn" disabled>Next &#9654;</button><span id="spinner" aria-hidden="true"></span></div>
+    <div id="dotStrip"></div><div class="keyboard-hint">Arrow keys: Previous / Next</div>
+  </div>
+  <div id="loading"><div id="loadSpinner"></div><div id="loadingText">Loading presentation…</div></div>
+  <script>if (window.self !== window.top) document.body.classList.add('in-iframe');</script>
+  <script>
+    var TS = {{TS}};
+    var N = TS.length, VW={{VW}}, VH={{VH}}, EPS=0.03;
+    var vid = document.getElementById('vid'), deckContainer = document.getElementById('deckContainer'), loading = document.getElementById('loading');
+    var current = 0, playing = false;
+    {{SECURE_EMBED_SCRIPT}}
+
+    // Rest = the PAUSED video frame at this slide's keyframe timestamp.
+    function settleOn(i){
+      current = i; playing = false;
+      try { vid.pause(); vid.currentTime = TS[i]; } catch(e){}
+      updateControls(); reportHeight();
+    }
+    function updateControls(){
+      document.getElementById('prevBtn').disabled = current<=0 || playing;
+      document.getElementById('nextBtn').disabled = current>=N-1 || playing;
+      document.getElementById('slideCounter').textContent = (current+1)+' of '+N;
+      var dots = document.querySelectorAll('.dot');
+      for (var k=0;k<dots.length;k++) dots[k].classList.toggle('active', k===current);
+    }
+    // Next: play the real transition to the next slide, then pause on its keyframe.
+    function next(){
+      if (playing || current>=N-1) return;
+      playing = true; setBusy(true); updateControls();
+      var target = TS[current+1];
+      function go(){
+        var lastT = -1, stalls = 0;
+        var pp = vid.play(); if (pp && pp.catch) pp.catch(function(){});
+        function watch(){
+          if (!playing) return;
+          var t = vid.currentTime;
+          if (t >= target - EPS || vid.ended){
+            vid.pause(); current++; playing = false;
+            try { vid.currentTime = TS[current]; } catch(e){}
+            setBusy(false); updateControls(); reportHeight(); return;
+          }
+          if (!vid.seeking && Math.abs(t - lastT) < 0.0004){
+            if (++stalls > 20){ var p2 = vid.play(); if (p2 && p2.catch) p2.catch(function(){}); stalls = 0; }
+          } else stalls = 0;
+          lastT = t;
+          requestAnimationFrame(watch);
+        }
+        requestAnimationFrame(watch);
+      }
+      // Don't start the transition until any in-progress seek settles AND we're
+      // parked at this slide's frame — otherwise play() races the seek and freezes.
+      if (vid.seeking || Math.abs(vid.currentTime - TS[current]) > 0.1){
+        var onSeeked = function(){ vid.removeEventListener('seeked', onSeeked); go(); };
+        vid.addEventListener('seeked', onSeeked);
+        try { vid.currentTime = TS[current]; } catch(e){ vid.removeEventListener('seeked', onSeeked); go(); }
+      } else { go(); }
+    }
+    function prev(){ if (playing || current<=0) return; settleOn(current-1); }
+    function jump(i){ if (playing) return; settleOn(i); }
+
+    function reportHeight(){
+      if (window.self===window.top) return;
+      var avail = document.documentElement.clientWidth - 32, dw=Math.min(avail,VW), dh=dw*(VH/VW);
+      var v=document.getElementById('viewer'); var ch=v?v.offsetHeight:80;
+      window.parent.postMessage({ type:'kd-viewer-height', height: Math.ceil(dh+ch+14+24+8) }, '*');
+    }
+    var rt=null; function sched(){ if(rt)clearTimeout(rt); rt=setTimeout(reportHeight,80); }
+    window.addEventListener('resize', sched);
+    if (window.ResizeObserver){ try{ new ResizeObserver(sched).observe(document.documentElement);}catch(e){} }
+
+    var dotStrip = document.getElementById('dotStrip');
+    for (var i=0;i<N;i++){ (function(idx){ var d=document.createElement('button'); d.className='dot'; d.title='Slide '+(idx+1); d.onclick=function(){ jump(idx); }; dotStrip.appendChild(d); })(i); }
+    document.getElementById('nextBtn').onclick = next;
+    document.getElementById('prevBtn').onclick = prev;
+    document.addEventListener('keydown', function(e){ if(e.key==='ArrowRight')next(); if(e.key==='ArrowLeft')prev(); });
+
+    // Busy spinner (controls row only) — shows while seeking (jumps) or playing a
+    // transition; never overlays the slide.
+    function setBusy(b){ document.body.classList.toggle('busy', b); }
+    vid.addEventListener('seeking', function(){ setBusy(true); });
+    vid.addEventListener('seeked', function(){ if(!playing && !vid.seeking) setBusy(false); });
+
+    function startUp(){
+      loading.style.display='none'; document.getElementById('viewer').style.display='flex'; document.body.classList.add('viewer-ready');
+      if (document.body.classList.contains('in-iframe')) deckContainer.style.maxWidth = VW+'px';
+      settleOn(0); setTimeout(reportHeight,250); setTimeout(reportHeight,700);
+    }
+    if (vid.readyState >= 1) startUp(); else vid.addEventListener('loadedmetadata', startUp, { once:true });
+    vid.addEventListener('error', function(){ document.getElementById('loadingText').textContent='Video failed to load.'; });
+  </script>
+</body></html>
\ No newline at end of file
diff --git a/swift-app/Sources/Services/VideoViewerGenerator.swift b/swift-app/Sources/Services/VideoViewerGenerator.swift
new file mode 100644
index 0000000..0c4b04e
--- /dev/null
+++ b/swift-app/Sources/Services/VideoViewerGenerator.swift
@@ -0,0 +1,75 @@
+import Foundation
+
+/// Generates the deployable `index.html` for the H.264 video deck viewer.
+///
+/// Mirrors Electron's `generateVideoViewerHtml()` (`electron/videoViewerGenerator.ts`)
+/// byte-for-byte. The full HTML/CSS/JS lives in the bundled resource
+/// `video-viewer-template.html` with interpolated values replaced by `{{TOKEN}}`
+/// placeholders. `generate(...)` loads the template from `Bundle.main`, fills the
+/// tokens in a single pass (no re-scan of injected values — matches the GIF port's
+/// parity discipline), and returns the result.
+///
+/// Pure `enum` with `static` funcs → trivially `Sendable`/concurrency-safe.
+enum VideoViewerGenerator {
+
+    /// Returns the deployable index.html for the video viewer.
+    /// Output is byte-identical to Electron's `generateVideoViewerHtml()` for
+    /// identical inputs.
+    ///
+    /// - Parameters:
+    ///   - videoFilename: bare filename, e.g. `deck.mp4` (lands in `src="./<file>"`).
+    ///   - secureEmbed: when true, injects the no-select CSS + contextmenu-block script.
+    ///   - timestamps: per-slide keyframe seconds; emitted as compact JSON (`{{TS}}`).
+    ///   - videoWidth: pixel width (default 1920, mirrors Electron).
+    ///   - videoHeight: pixel height (default 1080, mirrors Electron).
+    static func generate(videoFilename: String,
+                         secureEmbed: Bool,
+                         timestamps: [Double],
+                         videoWidth: Int = 1920,
+                         videoHeight: Int = 1080) -> String {
+        // The template is a required bundled resource. A missing template is a
+        // build/packaging bug, never a runtime-recoverable condition.
+        guard let url = Bundle.main.url(forResource: "video-viewer-template", withExtension: "html"),
+              let template = try? String(contentsOf: url, encoding: .utf8) else {
+            fatalError("video-viewer-template.html missing from app bundle — resource bundling is broken (see project.yml Sources/Resources).")
+        }
+
+        // {{TS}} — compact JSON matching JS `JSON.stringify([…])` (no spaces; no
+        // trailing zeros; integer values have no decimal point). Empty -> "[]".
+        let ts = "[" + timestamps.map(jsNumber).joined(separator: ",") + "]"
+
+        let secureEmbedCss = secureEmbed
+            ? "body { user-select: none; } #deck video { pointer-events: none; }"
+            : ""
+        let secureEmbedScript = secureEmbed
+            ? "document.addEventListener('contextmenu', function(e){ e.preventDefault(); });"
+            : ""
+
+        // Single-pass fill: each token replaced exactly once across the original
+        // template. Injected values never contain `{{…}}`, and the token strings
+        // do not overlap, so replacement order is irrelevant for correctness.
+        return template
+            .replacingOccurrences(of: "{{VIDEO_FILENAME}}", with: videoFilename)
+            .replacingOccurrences(of: "{{TS}}", with: ts)
+            .replacingOccurrences(of: "{{VW}}", with: String(videoWidth))
+            .replacingOccurrences(of: "{{VH}}", with: String(videoHeight))
+            .replacingOccurrences(of: "{{SECURE_EMBED_CSS}}", with: secureEmbedCss)
+            .replacingOccurrences(of: "{{SECURE_EMBED_SCRIPT}}", with: secureEmbedScript)
+    }
+
+    /// Format a `Double` the way JavaScript `JSON.stringify` would: integer values
+    /// render with no decimal point (`12` not `12.0`), fractionals strip trailing
+    /// zeros (`5.6` not `5.600`). Upstream timestamps are rounded to 3 decimals
+    /// (`round((t/fps)*1000)/1000`), so 3-place formatting + trailing-zero strip
+    /// is sufficient and byte-matches JS for all expected inputs. The golden
+    /// byte-parity test is the authoritative confirmation.
+    private static func jsNumber(_ x: Double) -> String {
+        if x.isFinite && x == x.rounded() {
+            return String(Int(x))
+        }
+        var s = String(format: "%.3f", x)
+        while s.hasSuffix("0") { s.removeLast() }
+        if s.hasSuffix(".") { s.removeLast() }
+        return s
+    }
+}
diff --git a/swift-app/Tests/Fixtures/video-viewer-golden-plain.html b/swift-app/Tests/Fixtures/video-viewer-golden-plain.html
new file mode 100644
index 0000000..f7962b2
--- /dev/null
+++ b/swift-app/Tests/Fixtures/video-viewer-golden-plain.html
@@ -0,0 +1,139 @@
+<!DOCTYPE html>
+<html lang="en"><head>
+<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
+<title>Keynote Slide Viewer</title>
+<style>
+  * { margin:0; padding:0; box-sizing:border-box; }
+  body { background:#0a0a0a; color:#e5e5e5; font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif; min-height:100vh; display:flex; flex-direction:column; align-items:center; }
+  header { width:100%; background:#111; border-bottom:1px solid #222; padding:14px 24px; text-align:center; } header h1 { font-size:16px; font-weight:600; }
+  #deckContainer { display:none; width:100%; max-width:1024px; margin:24px auto 0; padding:0 16px; }
+  #deck { position:relative; width:100%; aspect-ratio:1024/768; background:#111; border:1px solid #222; border-radius:8px; overflow:hidden; }
+  #deck video { position:absolute; inset:0; width:100%; height:100%; object-fit:contain; display:block; background:#0a0a0a; }
+  #viewer { display:none; width:100%; max-width:1024px; margin:16px auto 0; padding:0 16px 32px; flex-direction:column; align-items:center; gap:12px; }
+  .controls-row { display:flex; align-items:center; gap:16px; }
+  #slideCounter { font-size:13px; color:#999; min-width:80px; text-align:center; }
+  #dotStrip { display:flex; align-items:center; justify-content:center; flex-wrap:wrap; gap:0; max-width:100%; padding:4px 0; }
+  .dot { width:8px; height:8px; border-radius:50%; background:#333; border:none; padding:0; margin:0 2px; cursor:pointer; min-width:8px; transition:background .1s; } .dot.active{background:#3b82f6;} .dot:hover{background:#555;}
+  button { padding:8px 16px; background:#222; border:1px solid #333; border-radius:6px; color:#ccc; font-size:13px; cursor:pointer; } button:hover{background:#333;} button:disabled{opacity:.3;cursor:default;}
+  .keyboard-hint { font-size:11px; color:#555; }
+  #spinner { width:14px; height:14px; border:2px solid #333; border-top-color:#3b82f6; border-radius:50%; display:none; flex:0 0 auto; }
+  body.busy #spinner { display:inline-block; animation:kd-spin .7s linear infinite; }
+  @keyframes kd-spin { to { transform:rotate(360deg); } }
+  body.in-iframe #spinner { width:clamp(14px,1.5vw,20px); height:clamp(14px,1.5vw,20px); }
+  #loading { display:flex; position:fixed; inset:0; background:rgba(10,10,10,.92); z-index:100; flex-direction:column; align-items:center; justify-content:center; gap:16px; } #loadingText{font-size:14px;color:#999;}
+  #loadSpinner { width:40px; height:40px; border:3px solid rgba(255,255,255,.12); border-top-color:#3b82f6; border-radius:50%; animation:kd-spin .8s linear infinite; }
+  body.viewer-ready #deckContainer { display:block; }
+  @media all {
+    body.in-iframe header, body.in-iframe .keyboard-hint, body.in-iframe .powered-by { display:none !important; }
+    body.in-iframe { height:100vh; overflow:hidden; justify-content:safe center; gap:14px; padding:12px 0; background:transparent; }
+    body.in-iframe.viewer-ready #deckContainer { display:flex; align-items:center; justify-content:center; flex:1 1 auto; min-height:0; max-width:none; width:100%; margin:0; padding:0 16px; }
+    body.in-iframe #deck { width:auto; height:100%; max-width:100%; aspect-ratio:1024/768; background:transparent; border:none; border-radius:0; }
+    body.in-iframe #deck video { background:transparent; }
+    body.in-iframe #viewer { flex:0 0 auto; max-width:none; width:100%; margin:0; padding:0 16px; }
+    body.in-iframe .controls-row { gap:clamp(16px,1.8vw,28px); }
+    body.in-iframe .controls-row button { font-size:clamp(13px,1.4vw,17px); padding:clamp(8px,.9vw,12px) clamp(16px,1.8vw,24px); border-radius:clamp(6px,.6vw,9px); }
+    body.in-iframe #slideCounter { font-size:clamp(13px,1.4vw,17px); min-width:clamp(80px,8vw,110px); }
+    body.in-iframe .dot { width:clamp(8px,.9vw,11px); height:clamp(8px,.9vw,11px); min-width:clamp(8px,.9vw,11px); margin:0 clamp(2px,.25vw,4px); }
+    body.in-iframe #dotStrip { row-gap:6px; }
+    body.in-iframe #loading { background:transparent; } body.in-iframe #loadingText { background:rgba(10,10,10,.82); padding:8px 16px; border-radius:8px; backdrop-filter:blur(4px); }
+  }
+  /* Narrow embeds (phones): the dots wrap into rows and waste height + are too
+     small to tap — drop them, keep Prev/Next + the "X of N" counter. */
+  @media (max-width:549px){ #dotStrip { display:none !important; } }
+  
+</style></head>
+<body>
+  <header><h1>Keynote Slide Viewer</h1></header>
+  <div id="deckContainer"><div id="deck"><video id="vid" muted playsinline preload="auto" src="./slides.mp4"></video></div></div>
+  <div id="viewer">
+    <div class="controls-row"><button id="prevBtn" disabled>&#9664; Previous</button><span id="slideCounter">Slide 0 / 0</span><button id="nextBtn" disabled>Next &#9654;</button><span id="spinner" aria-hidden="true"></span></div>
+    <div id="dotStrip"></div><div class="keyboard-hint">Arrow keys: Previous / Next</div>
+  </div>
+  <div id="loading"><div id="loadSpinner"></div><div id="loadingText">Loading presentation…</div></div>
+  <script>if (window.self !== window.top) document.body.classList.add('in-iframe');</script>
+  <script>
+    var TS = [0,2.5,7];
+    var N = TS.length, VW=1024, VH=768, EPS=0.03;
+    var vid = document.getElementById('vid'), deckContainer = document.getElementById('deckContainer'), loading = document.getElementById('loading');
+    var current = 0, playing = false;
+    
+
+    // Rest = the PAUSED video frame at this slide's keyframe timestamp.
+    function settleOn(i){
+      current = i; playing = false;
+      try { vid.pause(); vid.currentTime = TS[i]; } catch(e){}
+      updateControls(); reportHeight();
+    }
+    function updateControls(){
+      document.getElementById('prevBtn').disabled = current<=0 || playing;
+      document.getElementById('nextBtn').disabled = current>=N-1 || playing;
+      document.getElementById('slideCounter').textContent = (current+1)+' of '+N;
+      var dots = document.querySelectorAll('.dot');
+      for (var k=0;k<dots.length;k++) dots[k].classList.toggle('active', k===current);
+    }
+    // Next: play the real transition to the next slide, then pause on its keyframe.
+    function next(){
+      if (playing || current>=N-1) return;
+      playing = true; setBusy(true); updateControls();
+      var target = TS[current+1];
+      function go(){
+        var lastT = -1, stalls = 0;
+        var pp = vid.play(); if (pp && pp.catch) pp.catch(function(){});
+        function watch(){
+          if (!playing) return;
+          var t = vid.currentTime;
+          if (t >= target - EPS || vid.ended){
+            vid.pause(); current++; playing = false;
+            try { vid.currentTime = TS[current]; } catch(e){}
+            setBusy(false); updateControls(); reportHeight(); return;
+          }
+          if (!vid.seeking && Math.abs(t - lastT) < 0.0004){
+            if (++stalls > 20){ var p2 = vid.play(); if (p2 && p2.catch) p2.catch(function(){}); stalls = 0; }
+          } else stalls = 0;
+          lastT = t;
+          requestAnimationFrame(watch);
+        }
+        requestAnimationFrame(watch);
+      }
+      // Don't start the transition until any in-progress seek settles AND we're
+      // parked at this slide's frame — otherwise play() races the seek and freezes.
+      if (vid.seeking || Math.abs(vid.currentTime - TS[current]) > 0.1){
+        var onSeeked = function(){ vid.removeEventListener('seeked', onSeeked); go(); };
+        vid.addEventListener('seeked', onSeeked);
+        try { vid.currentTime = TS[current]; } catch(e){ vid.removeEventListener('seeked', onSeeked); go(); }
+      } else { go(); }
+    }
+    function prev(){ if (playing || current<=0) return; settleOn(current-1); }
+    function jump(i){ if (playing) return; settleOn(i); }
+
+    function reportHeight(){
+      if (window.self===window.top) return;
+      var avail = document.documentElement.clientWidth - 32, dw=Math.min(avail,VW), dh=dw*(VH/VW);
+      var v=document.getElementById('viewer'); var ch=v?v.offsetHeight:80;
+      window.parent.postMessage({ type:'kd-viewer-height', height: Math.ceil(dh+ch+14+24+8) }, '*');
+    }
+    var rt=null; function sched(){ if(rt)clearTimeout(rt); rt=setTimeout(reportHeight,80); }
+    window.addEventListener('resize', sched);
+    if (window.ResizeObserver){ try{ new ResizeObserver(sched).observe(document.documentElement);}catch(e){} }
+
+    var dotStrip = document.getElementById('dotStrip');
+    for (var i=0;i<N;i++){ (function(idx){ var d=document.createElement('button'); d.className='dot'; d.title='Slide '+(idx+1); d.onclick=function(){ jump(idx); }; dotStrip.appendChild(d); })(i); }
+    document.getElementById('nextBtn').onclick = next;
+    document.getElementById('prevBtn').onclick = prev;
+    document.addEventListener('keydown', function(e){ if(e.key==='ArrowRight')next(); if(e.key==='ArrowLeft')prev(); });
+
+    // Busy spinner (controls row only) — shows while seeking (jumps) or playing a
+    // transition; never overlays the slide.
+    function setBusy(b){ document.body.classList.toggle('busy', b); }
+    vid.addEventListener('seeking', function(){ setBusy(true); });
+    vid.addEventListener('seeked', function(){ if(!playing && !vid.seeking) setBusy(false); });
+
+    function startUp(){
+      loading.style.display='none'; document.getElementById('viewer').style.display='flex'; document.body.classList.add('viewer-ready');
+      if (document.body.classList.contains('in-iframe')) deckContainer.style.maxWidth = VW+'px';
+      settleOn(0); setTimeout(reportHeight,250); setTimeout(reportHeight,700);
+    }
+    if (vid.readyState >= 1) startUp(); else vid.addEventListener('loadedmetadata', startUp, { once:true });
+    vid.addEventListener('error', function(){ document.getElementById('loadingText').textContent='Video failed to load.'; });
+  </script>
+</body></html>
\ No newline at end of file
diff --git a/swift-app/Tests/Fixtures/video-viewer-golden-secure.html b/swift-app/Tests/Fixtures/video-viewer-golden-secure.html
new file mode 100644
index 0000000..f294600
--- /dev/null
+++ b/swift-app/Tests/Fixtures/video-viewer-golden-secure.html
@@ -0,0 +1,139 @@
+<!DOCTYPE html>
+<html lang="en"><head>
+<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
+<title>Keynote Slide Viewer</title>
+<style>
+  * { margin:0; padding:0; box-sizing:border-box; }
+  body { background:#0a0a0a; color:#e5e5e5; font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif; min-height:100vh; display:flex; flex-direction:column; align-items:center; }
+  header { width:100%; background:#111; border-bottom:1px solid #222; padding:14px 24px; text-align:center; } header h1 { font-size:16px; font-weight:600; }
+  #deckContainer { display:none; width:100%; max-width:1920px; margin:24px auto 0; padding:0 16px; }
+  #deck { position:relative; width:100%; aspect-ratio:1920/1080; background:#111; border:1px solid #222; border-radius:8px; overflow:hidden; }
+  #deck video { position:absolute; inset:0; width:100%; height:100%; object-fit:contain; display:block; background:#0a0a0a; }
+  #viewer { display:none; width:100%; max-width:1920px; margin:16px auto 0; padding:0 16px 32px; flex-direction:column; align-items:center; gap:12px; }
+  .controls-row { display:flex; align-items:center; gap:16px; }
+  #slideCounter { font-size:13px; color:#999; min-width:80px; text-align:center; }
+  #dotStrip { display:flex; align-items:center; justify-content:center; flex-wrap:wrap; gap:0; max-width:100%; padding:4px 0; }
+  .dot { width:8px; height:8px; border-radius:50%; background:#333; border:none; padding:0; margin:0 2px; cursor:pointer; min-width:8px; transition:background .1s; } .dot.active{background:#3b82f6;} .dot:hover{background:#555;}
+  button { padding:8px 16px; background:#222; border:1px solid #333; border-radius:6px; color:#ccc; font-size:13px; cursor:pointer; } button:hover{background:#333;} button:disabled{opacity:.3;cursor:default;}
+  .keyboard-hint { font-size:11px; color:#555; }
+  #spinner { width:14px; height:14px; border:2px solid #333; border-top-color:#3b82f6; border-radius:50%; display:none; flex:0 0 auto; }
+  body.busy #spinner { display:inline-block; animation:kd-spin .7s linear infinite; }
+  @keyframes kd-spin { to { transform:rotate(360deg); } }
+  body.in-iframe #spinner { width:clamp(14px,1.5vw,20px); height:clamp(14px,1.5vw,20px); }
+  #loading { display:flex; position:fixed; inset:0; background:rgba(10,10,10,.92); z-index:100; flex-direction:column; align-items:center; justify-content:center; gap:16px; } #loadingText{font-size:14px;color:#999;}
+  #loadSpinner { width:40px; height:40px; border:3px solid rgba(255,255,255,.12); border-top-color:#3b82f6; border-radius:50%; animation:kd-spin .8s linear infinite; }
+  body.viewer-ready #deckContainer { display:block; }
+  @media all {
+    body.in-iframe header, body.in-iframe .keyboard-hint, body.in-iframe .powered-by { display:none !important; }
+    body.in-iframe { height:100vh; overflow:hidden; justify-content:safe center; gap:14px; padding:12px 0; background:transparent; }
+    body.in-iframe.viewer-ready #deckContainer { display:flex; align-items:center; justify-content:center; flex:1 1 auto; min-height:0; max-width:none; width:100%; margin:0; padding:0 16px; }
+    body.in-iframe #deck { width:auto; height:100%; max-width:100%; aspect-ratio:1920/1080; background:transparent; border:none; border-radius:0; }
+    body.in-iframe #deck video { background:transparent; }
+    body.in-iframe #viewer { flex:0 0 auto; max-width:none; width:100%; margin:0; padding:0 16px; }
+    body.in-iframe .controls-row { gap:clamp(16px,1.8vw,28px); }
+    body.in-iframe .controls-row button { font-size:clamp(13px,1.4vw,17px); padding:clamp(8px,.9vw,12px) clamp(16px,1.8vw,24px); border-radius:clamp(6px,.6vw,9px); }
+    body.in-iframe #slideCounter { font-size:clamp(13px,1.4vw,17px); min-width:clamp(80px,8vw,110px); }
+    body.in-iframe .dot { width:clamp(8px,.9vw,11px); height:clamp(8px,.9vw,11px); min-width:clamp(8px,.9vw,11px); margin:0 clamp(2px,.25vw,4px); }
+    body.in-iframe #dotStrip { row-gap:6px; }
+    body.in-iframe #loading { background:transparent; } body.in-iframe #loadingText { background:rgba(10,10,10,.82); padding:8px 16px; border-radius:8px; backdrop-filter:blur(4px); }
+  }
+  /* Narrow embeds (phones): the dots wrap into rows and waste height + are too
+     small to tap — drop them, keep Prev/Next + the "X of N" counter. */
+  @media (max-width:549px){ #dotStrip { display:none !important; } }
+  body { user-select: none; } #deck video { pointer-events: none; }
+</style></head>
+<body>
+  <header><h1>Keynote Slide Viewer</h1></header>
+  <div id="deckContainer"><div id="deck"><video id="vid" muted playsinline preload="auto" src="./deck.mp4"></video></div></div>
+  <div id="viewer">
+    <div class="controls-row"><button id="prevBtn" disabled>&#9664; Previous</button><span id="slideCounter">Slide 0 / 0</span><button id="nextBtn" disabled>Next &#9654;</button><span id="spinner" aria-hidden="true"></span></div>
+    <div id="dotStrip"></div><div class="keyboard-hint">Arrow keys: Previous / Next</div>
+  </div>
+  <div id="loading"><div id="loadSpinner"></div><div id="loadingText">Loading presentation…</div></div>
+  <script>if (window.self !== window.top) document.body.classList.add('in-iframe');</script>
+  <script>
+    var TS = [0,1.234,5.6,12];
+    var N = TS.length, VW=1920, VH=1080, EPS=0.03;
+    var vid = document.getElementById('vid'), deckContainer = document.getElementById('deckContainer'), loading = document.getElementById('loading');
+    var current = 0, playing = false;
+    document.addEventListener('contextmenu', function(e){ e.preventDefault(); });
+
+    // Rest = the PAUSED video frame at this slide's keyframe timestamp.
+    function settleOn(i){
+      current = i; playing = false;
+      try { vid.pause(); vid.currentTime = TS[i]; } catch(e){}
+      updateControls(); reportHeight();
+    }
+    function updateControls(){
+      document.getElementById('prevBtn').disabled = current<=0 || playing;
+      document.getElementById('nextBtn').disabled = current>=N-1 || playing;
+      document.getElementById('slideCounter').textContent = (current+1)+' of '+N;
+      var dots = document.querySelectorAll('.dot');
+      for (var k=0;k<dots.length;k++) dots[k].classList.toggle('active', k===current);
+    }
+    // Next: play the real transition to the next slide, then pause on its keyframe.
+    function next(){
+      if (playing || current>=N-1) return;
+      playing = true; setBusy(true); updateControls();
+      var target = TS[current+1];
+      function go(){
+        var lastT = -1, stalls = 0;
+        var pp = vid.play(); if (pp && pp.catch) pp.catch(function(){});
+        function watch(){
+          if (!playing) return;
+          var t = vid.currentTime;
+          if (t >= target - EPS || vid.ended){
+            vid.pause(); current++; playing = false;
+            try { vid.currentTime = TS[current]; } catch(e){}
+            setBusy(false); updateControls(); reportHeight(); return;
+          }
+          if (!vid.seeking && Math.abs(t - lastT) < 0.0004){
+            if (++stalls > 20){ var p2 = vid.play(); if (p2 && p2.catch) p2.catch(function(){}); stalls = 0; }
+          } else stalls = 0;
+          lastT = t;
+          requestAnimationFrame(watch);
+        }
+        requestAnimationFrame(watch);
+      }
+      // Don't start the transition until any in-progress seek settles AND we're
+      // parked at this slide's frame — otherwise play() races the seek and freezes.
+      if (vid.seeking || Math.abs(vid.currentTime - TS[current]) > 0.1){
+        var onSeeked = function(){ vid.removeEventListener('seeked', onSeeked); go(); };
+        vid.addEventListener('seeked', onSeeked);
+        try { vid.currentTime = TS[current]; } catch(e){ vid.removeEventListener('seeked', onSeeked); go(); }
+      } else { go(); }
+    }
+    function prev(){ if (playing || current<=0) return; settleOn(current-1); }
+    function jump(i){ if (playing) return; settleOn(i); }
+
+    function reportHeight(){
+      if (window.self===window.top) return;
+      var avail = document.documentElement.clientWidth - 32, dw=Math.min(avail,VW), dh=dw*(VH/VW);
+      var v=document.getElementById('viewer'); var ch=v?v.offsetHeight:80;
+      window.parent.postMessage({ type:'kd-viewer-height', height: Math.ceil(dh+ch+14+24+8) }, '*');
+    }
+    var rt=null; function sched(){ if(rt)clearTimeout(rt); rt=setTimeout(reportHeight,80); }
+    window.addEventListener('resize', sched);
+    if (window.ResizeObserver){ try{ new ResizeObserver(sched).observe(document.documentElement);}catch(e){} }
+
+    var dotStrip = document.getElementById('dotStrip');
+    for (var i=0;i<N;i++){ (function(idx){ var d=document.createElement('button'); d.className='dot'; d.title='Slide '+(idx+1); d.onclick=function(){ jump(idx); }; dotStrip.appendChild(d); })(i); }
+    document.getElementById('nextBtn').onclick = next;
+    document.getElementById('prevBtn').onclick = prev;
+    document.addEventListener('keydown', function(e){ if(e.key==='ArrowRight')next(); if(e.key==='ArrowLeft')prev(); });
+
+    // Busy spinner (controls row only) — shows while seeking (jumps) or playing a
+    // transition; never overlays the slide.
+    function setBusy(b){ document.body.classList.toggle('busy', b); }
+    vid.addEventListener('seeking', function(){ setBusy(true); });
+    vid.addEventListener('seeked', function(){ if(!playing && !vid.seeking) setBusy(false); });
+
+    function startUp(){
+      loading.style.display='none'; document.getElementById('viewer').style.display='flex'; document.body.classList.add('viewer-ready');
+      if (document.body.classList.contains('in-iframe')) deckContainer.style.maxWidth = VW+'px';
+      settleOn(0); setTimeout(reportHeight,250); setTimeout(reportHeight,700);
+    }
+    if (vid.readyState >= 1) startUp(); else vid.addEventListener('loadedmetadata', startUp, { once:true });
+    vid.addEventListener('error', function(){ document.getElementById('loadingText').textContent='Video failed to load.'; });
+  </script>
+</body></html>
\ No newline at end of file
diff --git a/swift-app/Tests/VideoViewerGeneratorTests.swift b/swift-app/Tests/VideoViewerGeneratorTests.swift
new file mode 100644
index 0000000..c1ca6f3
--- /dev/null
+++ b/swift-app/Tests/VideoViewerGeneratorTests.swift
@@ -0,0 +1,121 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+/// Parity gate for the video viewer generator. The golden fixtures in
+/// `Tests/Fixtures/` were captured by running the SAME inputs through the
+/// TypeScript `generateVideoViewerHtml` (`electron/videoViewerGenerator.ts`)
+/// via `node`, so they are the byte-parity oracle.
+@Suite("Section 3 — VideoViewerGenerator parity")
+struct VideoViewerGeneratorTests {
+
+    // Fixtures live next to this source file (loaded off disk, not the test
+    // bundle, so no resource-bundling wiring is required for the goldens).
+    private func goldenString(_ name: String, file: String = #filePath) throws -> String {
+        let url = URL(fileURLWithPath: file)
+            .deletingLastPathComponent()
+            .appendingPathComponent("Fixtures/\(name)")
+        return try String(contentsOf: url, encoding: .utf8)
+    }
+
+    /// The bundled template loads from Bundle.main at runtime (not nil).
+    /// Guards the resource-bundling wiring from section-01.
+    @Test func templateBundleResourceLoads() throws {
+        let url = Bundle.main.url(forResource: "video-viewer-template", withExtension: "html")
+        #expect(url != nil, "video-viewer-template.html must be bundled into Bundle.main")
+        let html = try String(contentsOf: #require(url), encoding: .utf8)
+        #expect(html.hasPrefix("<!DOCTYPE html>"))
+        #expect(html.contains("{{TS}}"))
+    }
+
+    /// BYTE-PARITY (secure branch): generate(...) == the Electron golden for
+    /// identical inputs (secureEmbed=true, default 1920x1080).
+    @Test func byteParityWithElectronGoldenSecure() throws {
+        let golden = try goldenString("video-viewer-golden-secure.html")
+        let output = VideoViewerGenerator.generate(
+            videoFilename: "deck.mp4",
+            secureEmbed: true,
+            timestamps: [0, 1.234, 5.6, 12],
+            videoWidth: 1920,
+            videoHeight: 1080
+        )
+        #expect(output == golden)
+    }
+
+    /// BYTE-PARITY (plain branch): secureEmbed=false + non-16:9 dimensions
+    /// (1024x768) to confirm every {{VW}}/{{VH}} site fills and both secure
+    /// tokens collapse to "".
+    @Test func byteParityWithElectronGoldenPlain() throws {
+        let golden = try goldenString("video-viewer-golden-plain.html")
+        let output = VideoViewerGenerator.generate(
+            videoFilename: "slides.mp4",
+            secureEmbed: false,
+            timestamps: [0, 2.5, 7],
+            videoWidth: 1024,
+            videoHeight: 768
+        )
+        #expect(output == golden)
+    }
+
+    /// {{TS}} is emitted as compact JSON with no spaces, matching JS
+    /// JSON.stringify. Integers render with no decimal point; empty -> [].
+    @Test func timestampsAreCompactJson() {
+        let out = VideoViewerGenerator.generate(
+            videoFilename: "deck.mp4", secureEmbed: false,
+            timestamps: [0, 1.234, 5.6, 12], videoWidth: 1920, videoHeight: 1080
+        )
+        #expect(out.contains("var TS = [0,1.234,5.6,12];"))
+        // no spaces after commas
+        #expect(!out.contains("[0, 1.234"))
+
+        let empty = VideoViewerGenerator.generate(
+            videoFilename: "deck.mp4", secureEmbed: false,
+            timestamps: [], videoWidth: 1920, videoHeight: 1080
+        )
+        #expect(empty.contains("var TS = [];"))
+    }
+
+    /// secureEmbed=true injects the EXACT css + contextmenu script strings;
+    /// secureEmbed=false omits both (tokens fill with "").
+    @Test func secureEmbedStringsExact() {
+        let on = VideoViewerGenerator.generate(
+            videoFilename: "deck.mp4", secureEmbed: true,
+            timestamps: [0], videoWidth: 1920, videoHeight: 1080
+        )
+        #expect(on.contains("body { user-select: none; } #deck video { pointer-events: none; }"))
+        #expect(on.contains("document.addEventListener('contextmenu', function(e){ e.preventDefault(); });"))
+
+        let off = VideoViewerGenerator.generate(
+            videoFilename: "deck.mp4", secureEmbed: false,
+            timestamps: [0], videoWidth: 1920, videoHeight: 1080
+        )
+        #expect(!off.contains("user-select: none"))
+        #expect(!off.contains("contextmenu"))
+        #expect(!off.contains("preventDefault"))
+    }
+
+    /// filename + width/height land in src="./<file>" and the aspect-ratio CSS
+    /// + JS vars. Confirms all token sites fill.
+    @Test func filenameAndDimensionsLandInTokens() {
+        let out = VideoViewerGenerator.generate(
+            videoFilename: "myDeck.mp4", secureEmbed: false,
+            timestamps: [0], videoWidth: 1600, videoHeight: 900
+        )
+        #expect(out.contains("src=\"./myDeck.mp4\""))
+        #expect(out.contains("aspect-ratio:1600/900"))
+        #expect(out.contains("VW=1600, VH=900"))
+        #expect(out.contains("max-width:1600px"))
+        // no leftover tokens
+        #expect(!out.contains("{{"))
+        #expect(!out.contains("}}"))
+    }
+
+    /// Default parameters mirror Electron (1920x1080) when omitted.
+    @Test func defaultDimensionsAre1920x1080() {
+        let out = VideoViewerGenerator.generate(
+            videoFilename: "deck.mp4", secureEmbed: false, timestamps: [0]
+        )
+        #expect(out.contains("aspect-ratio:1920/1080"))
+        #expect(out.contains("VW=1920, VH=1080"))
+    }
+}
