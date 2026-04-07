// =======================================================
// VoiceControl für FHEM
// Version: 0.9
// Datum: 20.03.2026
// Änderungen:
// - Mobile + Desktop getrennt
// - Desktop Fix: kein Selbsttriggern durch TTS
// - Desktop Fix: stabilerer Wakeword Flow
// =======================================================

(function() {
    function init() {
        if (document.getElementById("fhem-voice-btn")) return;

        let isJamesActive = false;
        let isSpeaking = false; 
        let pressTimer;
        let isHolding = false;
        let recognition;
        let selectedVoice = null;
        let isWaitingForCommand = false;
        let commandTimeout;
        let audioUnlocked = false; 
        let startupBlock = false;

        const COLOR_IDLE = "#3498db";
        const COLOR_READY = "#2ecc71";
        const COLOR_OFF = "#444";

        const wakewords = ["james"];
        const SpeechRecognition = (window.SpeechRecognition || window.webkitSpeechRecognition) || null;

        const isFully = (typeof fully !== 'undefined' && typeof fully.textToSpeech === 'function');
        const isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || isFully;

        function loadVoices() {
            if (isFully) return;
            try {
                const synth = window.speechSynthesis;
                if (!synth) return;
                const voices = synth.getVoices();
                selectedVoice = voices.find(v => v.name.includes("Stefan")) || 
                                voices.find(v => v.name.includes("Hans")) || 
                                voices.find(v => v.lang.startsWith("de"));
            } catch(e) {}
        }

        if (!isFully && window.speechSynthesis) {
            if ('onvoiceschanged' in window.speechSynthesis) window.speechSynthesis.onvoiceschanged = loadVoices;
            loadVoices();
        }

        function speak(text, callback) {
            if (!text || text === " ") { if(callback) callback(); return; }
            isSpeaking = true;

            if (isFully) {
                try {
                    fully.textToSpeech(text);
                    let duration = Math.max(1200, text.length * 85);
                    setTimeout(() => { isSpeaking = false; if(callback) callback(); }, duration);
                    return;
                } catch(e) {}
            }

            try {
                const synth = window.speechSynthesis;
                synth.cancel();
                const utter = new SpeechSynthesisUtterance(text);
                utter.lang = "de-DE";
                if (selectedVoice) utter.voice = selectedVoice;
                utter.onend = () => { isSpeaking = false; if(callback) callback(); };
                utter.onerror = () => { isSpeaking = false; if(callback) callback(); };
                synth.speak(utter);
            } catch(e) {
                isSpeaking = false;
                if(callback) callback();
            }
        }

        const btn = document.createElement("div");
        btn.id = "fhem-voice-btn";
        btn.innerHTML = "🎤";
        btn.style.cssText = `position: fixed; bottom: 20px; right: 20px; width: 60px; height: 60px; border-radius: 50%; background: ${COLOR_OFF}; color: white; font-size: 30px; display: flex; align-items: center; justify-content: center; cursor: pointer; z-index: 9999; transition: all 0.3s; box-shadow: 0 4px 10px rgba(0,0,0,0.3); user-select: none; touch-action: none;`;
        document.body.appendChild(btn);

        const bubble = document.createElement("div");
        bubble.id = "fhem-voice-bubble";
        bubble.style.cssText = `position: fixed; bottom: 95px; right: 20px; max-width: 220px; background: white; color: black; padding: 10px 14px; border-radius: 16px; font-size: 14px; box-shadow: 0 4px 10px rgba(0,0,0,0.3); display: none; z-index: 9999;`;
        document.body.appendChild(bubble);

        function showBubble(text, duration = 2500) {
            bubble.textContent = text;
            bubble.style.display = "block";
            setTimeout(() => bubble.style.display = "none", duration);
        }

        function processSpeech(text) {

            if (!isMobile) {
                if (isSpeaking || startupBlock) return;
                if (!isJamesActive && !isHolding && !isWaitingForCommand) return;
            }

            let spoken = text.toLowerCase().trim();
            if(spoken.length < 2) return;
            if(["aktiviert", "bereit", "okay", "ja?"].some(word => spoken.includes(word))) return;

            const wake = wakewords.find(w => new RegExp(`\\b${w}\\b`, "i").test(spoken));

            if (wake && !isWaitingForCommand) {
                isWaitingForCommand = true;
                btn.style.background = COLOR_READY; 
                showBubble("🤖 Ja?");
                try { recognition.stop(); } catch(e){}

                speak("Ja?", () => { try { recognition.start(); } catch(e){} });

                clearTimeout(commandTimeout);
                commandTimeout = setTimeout(() => {
                    if(isWaitingForCommand){
                        isWaitingForCommand = false;
                        btn.style.background = COLOR_IDLE; 
                        showBubble("⏳ Abgebrochen");
                    }
                }, 6000);
                return;
            }

            if(isWaitingForCommand && !isSpeaking){
                clearTimeout(commandTimeout);
                isWaitingForCommand = false;
                btn.style.background = COLOR_IDLE;
                sendAction(spoken);
                return;
            }

            if(isHolding && !isSpeaking) sendAction(spoken);
        }

        function sendAction(cmd) {
            showBubble("🎤 " + cmd);

            let clientId = $("body").attr("fw_id") || "no_fw_id";
            const fhemCmd = `setreading global STT ${cmd} [${clientId}]`;
            FW_cmd(FW_root + "?cmd=" + encodeURIComponent(fhemCmd) + "&XHR=1");

            if (isMobile) {
                speak("Okay", () => {
                    try {
                        if (recognition && (isJamesActive || isHolding || isWaitingForCommand)) {
                            recognition.start();
                        }
                    } catch(e) {}
                });
            } else {
                speak("Okay");
            }
        }

        if(SpeechRecognition){
            recognition = new SpeechRecognition();
            recognition.lang = "de-DE";
            recognition.continuous = true;
            recognition.interimResults = false;

            recognition.onresult = (e) => {
                if (!isMobile && isSpeaking) return;
                const res = e.results[e.results.length-1];
                if(res.isFinal) processSpeech(res[0].transcript);
            }

            recognition.onend = () => {
                if(isSpeaking) return;

                if (isMobile) {
                    if(isJamesActive || isHolding || isWaitingForCommand){
                        setTimeout(() => { try { recognition.start(); } catch(e){} }, 400);
                    }
                } else {
                    if (isWaitingForCommand) {
                        isWaitingForCommand = false;
                        btn.style.background = COLOR_IDLE;
                    }

                    if(isJamesActive || isHolding){
                        setTimeout(() => { try { recognition.start(); } catch(e){} }, 100);
                    }
                }
            }
        }

        const handleDown = (e) => {
            if(e.cancelable) e.preventDefault();
            if(!audioUnlocked){ speak(" "); audioUnlocked = true; }

            pressTimer = setTimeout(() => {
                pressTimer = null;
                isHolding = true;
                btn.style.background = "#f1c40f";
                showBubble("🎤 Höre...");
                try { recognition.start(); } catch(e){}
            }, 450);
        }

        const handleUp = (e) => {
            if(e.cancelable) e.preventDefault();

            if(pressTimer){
                clearTimeout(pressTimer);
                pressTimer = null;

                isJamesActive = !isJamesActive;
                btn.style.background = isJamesActive ? COLOR_IDLE : COLOR_OFF;

                if(isJamesActive){

                    if (!isMobile) {
                        startupBlock = true;
                        setTimeout(() => { startupBlock = false; }, 3000);
                    }

                    showBubble("🤖 Aktiv", 2000);
                    speak("James aktiviert");
                    try { recognition.start(); } catch(e){}

                }else{
                    isWaitingForCommand = false;
                    showBubble("😴 Aus", 2000);
                    speak("James deaktiviert");
                    try { recognition.stop(); } catch(e){}
                }

            }else if(isHolding){
                btn.style.background = isJamesActive ? COLOR_IDLE : COLOR_OFF;
                setTimeout(()=>{ 
                    isHolding=false; 
                    if(!isJamesActive) try { recognition.stop(); } catch(e){} 
                }, 800);
            }
        }

        btn.addEventListener("mousedown", handleDown);
        btn.addEventListener("touchstart", handleDown, {passive:false});
        btn.addEventListener("mouseup", handleUp);
        btn.addEventListener("touchend", handleUp, {passive:false});
    }

    if(document.readyState==="complete") init();
    else window.addEventListener("load", init);
})();