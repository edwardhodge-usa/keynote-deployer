import Foundation

/// Generates the index.html wrapper for processed Keynote exports.
/// Mirrors the Electron version's generateIndexHtml() in keynoteProcessor.ts.
enum IndexHtmlGenerator {

    private static let navBarReservedHeight = 80
    private static let reRenderDelays = [20, 50, 100, 200, 400]
    private static let reRenderPollInterval = 100
    private static let reRenderPollCount = 20
    private static let navKeyCodes = [37, 39, 33, 34]
    private static let systemFontStack = "-apple-system,BlinkMacSystemFont,\"Segoe UI\",Helvetica,Arial,sans-serif"

    static func generate(slideCount: Int, secureEmbed: Bool) -> String {
        let parts = [
            "<!doctype html>",
            "<html xmlns=\"http://www.w3.org/1999/xhtml\">",
            "<head>",
            "  <title>Keynote</title>",
            "  <meta name=\"viewport\" content=\"initial-scale=1,minimum-scale=1,maximum-scale=1,user-scalable=no,width=device-width\"/>",
            "  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"/>",
            "  <style>\(buildStyles())</style>",
            "</head>",
            "<body id=\"body\" bgcolor=\"black\">",
            buildBodyHtml(),
            "<script src=\"assets/player/main.js\"></script>",
            "<script>\(buildScript(slideCount: slideCount))</script>",
            secureEmbed ? "<script>\(buildSecureEmbedScript())</script>" : "",
            "</body>",
            "</html>",
        ].filter { !$0.isEmpty }

        return parts.joined(separator: "\n")
    }

    private static func buildStyles() -> String {
        """
        html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}\
        canvas{image-rendering:optimizeSpeed!important;image-rendering:-webkit-optimize-contrast!important;image-rendering:crisp-edges!important;image-rendering:pixelated!important;-ms-interpolation-mode:nearest-neighbor!important}\
        #stageArea{width:100vw;height:calc(100vh - \(navBarReservedHeight)px);position:relative;display:flex;align-items:center;justify-content:center}\
        #loadingOverlay{position:fixed;top:0;left:0;width:100%;height:100%;background:#000;z-index:10000;display:flex;align-items:center;justify-content:center;flex-direction:column;transition:opacity 0.4s ease}\
        #loadingOverlay.fade-out{opacity:0;pointer-events:none}\
        #loadingSpinner{width:36px;height:36px;border:3px solid rgba(255,255,255,0.1);border-top-color:rgba(255,255,255,0.6);border-radius:50%;animation:spin 0.8s linear infinite}\
        @keyframes spin{to{transform:rotate(360deg)}}\
        #loadingText{color:rgba(255,255,255,0.4);font-family:\(systemFontStack);font-size:13px;margin-top:16px}\
        #navBar{position:fixed;bottom:20px;left:0;right:0;display:flex;align-items:center;justify-content:center;gap:20px;z-index:9999;font-family:\(systemFontStack);user-select:none;-webkit-user-select:none;pointer-events:none}\
        #navBar button{background:rgba(50,50,50,0.7);color:#fff;border:1px solid rgba(255,255,255,0.15);border-radius:6px;padding:8px 20px;font-size:14px;cursor:pointer;transition:background 0.2s,border-color 0.2s;pointer-events:auto;backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px)}\
        #navBar button:hover{background:rgba(80,80,80,0.8);border-color:rgba(255,255,255,0.3)}\
        #navBar button:active{background:rgba(30,30,30,0.8)}\
        #slideCounter{color:rgba(255,255,255,0.5);font-size:14px;min-width:80px;text-align:center;pointer-events:auto}
        """
    }

    private static func buildBodyHtml() -> String {
        """
        <div id="loadingOverlay"><div id="loadingSpinner"></div><div id="loadingText">Loading presentation&hellip;</div></div>
        <div id="stageArea"><div id="stage" class="stage"></div><div id="hyperlinkPlane" class="stage"></div></div>
        <div id="slideshowNavigator"></div>
        <div id="slideNumberControl"></div>
        <div id="slideNumberDisplay"></div>
        <div id="helpPlacard"></div>
        <div id="waitingIndicator"><div id="waitingSpinner"></div></div>
        <div id="navBar">
          <button id="btnPrev">&#8592; Previous</button>
          <span id="slideCounter"></span>
          <button id="btnNext">Next &#8594;</button>
        </div>
        """
    }

    private static func buildScript(slideCount: Int) -> String {
        let delaysJson = "[\(reRenderDelays.map(String.init).joined(separator: ","))]"
        let navKeyCodesJson = "[\(navKeyCodes.map(String.init).joined(separator: ","))]"
        return """
        (function(){
          var overlay=document.getElementById('loadingOverlay');
          var counter=document.getElementById('slideCounter');
          var totalSlides=\(slideCount);
          var overlayRemoved=false;
          function removeOverlay(){if(overlayRemoved)return;overlayRemoved=true;overlay.classList.add('fade-out');setTimeout(function(){overlay.style.display='none'},500)}
          var checkReady=setInterval(function(){var canvases=document.querySelectorAll('#stage canvas, #stageArea canvas');if(canvases.length>0){clearInterval(checkReady);setTimeout(removeOverlay,300)}},100);
          setTimeout(function(){clearInterval(checkReady);removeOverlay()},5000);
          function getSlideFromHash(){var h=window.location.hash.replace('#','');var n=parseInt(h,10);return isNaN(n)?0:n}
          function updateCounter(){var scene=getSlideFromHash();var display=Math.min(scene+1,totalSlides);counter.textContent=display+' / '+totalSlides}
          function navigateSlide(e,keyCode,keyName){e.stopPropagation();e.preventDefault();document.dispatchEvent(new KeyboardEvent('keydown',{keyCode:keyCode,key:keyName,bubbles:true}));setTimeout(updateCounter,200)}
          document.getElementById('btnNext').addEventListener('click',function(e){navigateSlide(e,39,'ArrowRight')});
          document.getElementById('btnPrev').addEventListener('click',function(e){navigateSlide(e,37,'ArrowLeft')});
          var reRenderTimers=[];var pollingInterval=null;var delays=\(delaysJson);var navKeyCodes=\(navKeyCodesJson);
          function fireResize(){window.dispatchEvent(new Event('resize'))}
          function triggerReRenders(){reRenderTimers.forEach(function(t){clearTimeout(t)});reRenderTimers=[];if(pollingInterval){clearInterval(pollingInterval);pollingInterval=null}fireResize();for(var i=0;i<delays.length;i++){reRenderTimers.push(setTimeout(fireResize,delays[i]))}var pollCount=0;pollingInterval=setInterval(function(){fireResize();pollCount++;if(pollCount>=\(reRenderPollCount)){clearInterval(pollingInterval);pollingInterval=null}},\(reRenderPollInterval))}
          window.addEventListener('hashchange',triggerReRenders);
          document.addEventListener('keydown',function(e){for(var i=0;i<navKeyCodes.length;i++){if(e.keyCode===navKeyCodes[i]){triggerReRenders();return}}});
          window.addEventListener('hashchange',updateCounter);updateCounter();setTimeout(updateCounter,1000);setInterval(updateCounter,1000);
        })();
        """
    }

    private static func buildSecureEmbedScript() -> String {
        """
        (function(){
          document.addEventListener('contextmenu',function(e){e.preventDefault()});
          document.addEventListener('dragstart',function(e){e.preventDefault()});
          document.body.style.userSelect='none';
          document.body.style.webkitUserSelect='none';
          document.addEventListener('keydown',function(e){
            if((e.ctrlKey||e.metaKey)&&['s','p','u'].indexOf(e.key.toLowerCase())!==-1){e.preventDefault()}
          });
        })();
        """
    }
}
