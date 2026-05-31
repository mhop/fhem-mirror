// =======================================================
// VoiceControl für FHEM
// Version: 0.9.9.3 (inkl. Windows Voice Fix & FW_widgets Integration)
// =======================================================

(function() {
    function init() {
        if (document.getElementById("fhem-voice-btn")) return;

        let isJamesActive = false;
        let isSpeaking = false; 
        let isUserSpeaking = false; 
        let pressTimer;
        let isHolding = false;
        let recognition;
        let selectedVoice = null;
        let isWaitingForCommand = false;
        let commandTimeout;
        let audioUnlocked = false; 
        let startupBlock = false;

        let isDragging = false;
        let startX = 0;
        let startY = 0;
        let offsetButtonX = 0;
        let offsetButtonY = 0;
        const DRAG_THRESHOLD = 150; 

        const COLOR_IDLE = "#3498db";
        const COLOR_READY = "#2ecc71";
        const COLOR_OFF = "#444";

        const wakewords = ["james"];
        const SpeechRecognition = (window.SpeechRecognition || window.webkitSpeechRecognition) || null;

        const isFully = (typeof fully !== 'undefined' && typeof fully.textToSpeech === 'function');
        const isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || isFully;

        const WAKEWORDTRIGGER = "wakeword_detected";
        const SPEECHTRIGGER = "global-TTS_input";

        function updateWaveAnimation() {
            if (!btn) return;
            if (isSpeaking || isWaitingForCommand || isHolding) {
                btn.classList.add("waves-speaking");
            } else {
                btn.classList.remove("waves-speaking");
            }
        }

        function registerVoiceWidget() {
            if (typeof FW_widgets !== "undefined") {
                FW_widgets.voiceControlJames = {
                    updateLine: function(e) {
                        if (!e || e.length < 2) return;
                        const reading = e[0];
                        const value = e[1];

                        if (!isWaitingForCommand && !isSpeaking && 
                            (reading.endsWith("-wakeword") || value === WAKEWORDTRIGGER)) {
                            startAssistantSTTFromExternal();
                        }

                        if ((reading === SPEECHTRIGGER || reading.endsWith("-TTS_input")) && !reading.endsWith("-ts")) {
                            let txt = value.replace(/_/g, ' ').trim();
                            if (txt && txt !== "no" && txt !== "definition") {
                                showBubble("🤖 " + txt);
                                speak(txt);
                            }
                        }
                    }
                };
            }
        }

        function startAssistantSTTFromExternal() {
            if (isWaitingForCommand) return;
            isWaitingForCommand = true;
            btn.style.color = COLOR_READY;
            updateWaveAnimation();
            showBubble("🤖 Ja?");
            try { recognition.stop(); } catch(e){}

            speak("Ja?", () => {
                setTimeout(() => {
                    try { recognition.start(); } catch(e){} 
                    clearTimeout(commandTimeout);
                    commandTimeout = setTimeout(() => {
                        if (isWaitingForCommand && !isUserSpeaking) {
                            isWaitingForCommand = false;
                            try { recognition.stop(); } catch(e){}
                            btn.style.color = isJamesActive ? COLOR_IDLE : COLOR_OFF;
                            updateWaveAnimation();
                            showBubble("⏳ Abgebrochen");
                        }
                    }, 10000);
                }, 600);
            });
        }

        function loadVoices() {
            if (isFully) return;
            try {
                const synth = window.speechSynthesis;
                if (!synth) return;
                const voices = synth.getVoices();
                
                if (!voices || voices.length === 0) return;

                selectedVoice = voices.find(v => v.name.toLowerCase().includes("stefan")) || 
                                voices.find(v => v.name.toLowerCase().includes("hans")) || 
                                voices.find(v => v.name.toLowerCase().includes("hedda")) || 
                                voices.find(v => v.lang.startsWith("de-"));
            } catch(e) {}
        }

        if (!isFully && window.speechSynthesis) {
            window.speechSynthesis.onvoiceschanged = loadVoices;
            loadVoices();
        }

        function speak(text, callback) {
            if (!text || text === " ") { if(callback) callback(); return; }
            isSpeaking = true;
            updateWaveAnimation();

            if (isFully) {
                try {
                    fully.textToSpeech(text);
                    let duration = Math.max(1200, text.length * 85);
                    setTimeout(() => { 
                        isSpeaking = false; 
                        updateWaveAnimation(); 
                        if(callback) callback(); 
                    }, duration);
                    return;
                } catch(e) {}
            }
            try {
                const synth = window.speechSynthesis;
                synth.cancel();
                
                const utter = new SpeechSynthesisUtterance(text);
                utter.lang = "de-DE";
                
                if (selectedVoice) {
                    utter.voice = selectedVoice;
                }

                utter.onend = () => { 
                    isSpeaking = false; 
                    updateWaveAnimation(); 
                    if(callback) callback(); 
                    utter._self = null; 
                };
                utter.onerror = () => { 
                    isSpeaking = false; 
                    updateWaveAnimation(); 
                    if(callback) callback(); 
                    utter._self = null;
                };
                utter._self = utter; 
                synth.speak(utter);
            } catch(e) {
                isSpeaking = false;
                updateWaveAnimation();
                if(callback) callback();
            }
        }

        // --- WAVE STYLES INJEKTION START ---
        const style = document.createElement("style");
        style.id = "fhem-voice-styles";
        style.innerHTML = `
            #fhem-voice-btn {
                position: fixed; width: 60px; height: 50px; 
                background: transparent; display: flex; align-items: center; justify-content: center; gap: 4px;
                z-index: 9999; transition: color 0.3s, transform 0.2s; user-select: none; cursor: move; -webkit-tap-highlight-color: transparent;
            }
            #fhem-voice-btn span {
                display: inline-block; 
                width: 4px; 
                height: 4px; 
                border-radius: 50%;
                pointer-events: none;
                transition: height 0.3s ease, border-radius 0.3s ease, background-color 0.3s;
            }
            #fhem-voice-btn span:nth-child(1) { background-color: #4285F4; }
            #fhem-voice-btn span:nth-child(2) { background-color: #EA4335; }
            #fhem-voice-btn span:nth-child(3) { background-color: #FBBC05; }
            #fhem-voice-btn span:nth-child(4) { background-color: #4285F4; }
            #fhem-voice-btn span:nth-child(5) { background-color: #34A853; }

            #fhem-voice-btn.waves-speaking span {
                border-radius: 2px;
                background-color: currentColor;
            }
            #fhem-voice-btn.waves-speaking span:nth-child(1) { height: 8px; animation: fhemWaveLinePulse 1s ease-in-out infinite alternate; animation-delay: 0.1s; animation-duration: 0.8s; }
            #fhem-voice-btn.waves-speaking span:nth-child(2) { height: 18px; animation: fhemWaveLinePulse 1s ease-in-out infinite alternate; animation-delay: 0.3s; animation-duration: 0.9s; }
            #fhem-voice-btn.waves-speaking span:nth-child(3) { height: 28px; animation: fhemWaveLinePulse 1s ease-in-out infinite alternate; animation-delay: 0.0s; animation-duration: 0.7s; }
            #fhem-voice-btn.waves-speaking span:nth-child(4) { height: 14px; animation: fhemWaveLinePulse 1s ease-in-out infinite alternate; animation-delay: 0.4s; animation-duration: 1.1s; }
            #fhem-voice-btn.waves-speaking span:utter:nth-child(5) { height: 24px; animation: fhemWaveLinePulse 1s ease-in-out infinite alternate; animation-delay: 0.2s; animation-duration: 0.8s; }

            @keyframes fhemWaveLinePulse {
                0% { transform: scaleY(0.3); }
                100% { transform: scaleY(1.5); }
            }
            #fhem-voice-btn:active { transform: scale(0.95); }
        `;
        document.head.appendChild(style);
        // --- WAVE STYLES INJEKTION ENDE ---

        const savedLeft = localStorage.getItem("jamesBtnLeft") || (window.innerWidth - 80) + "px";
        const savedTop = localStorage.getItem("jamesBtnTop") || (window.innerHeight - 70) + "px";

        const btn = document.createElement("div");
        btn.id = "fhem-voice-btn";
        btn.innerHTML = "<span></span><span></span><span></span><span></span><span></span>";
        btn.style.color = COLOR_OFF;
        btn.style.left = savedLeft;
        btn.style.top = savedTop;
        document.body.appendChild(btn);

        const bubble = document.createElement("div");
        bubble.id = "fhem-voice-bubble";
        bubble.style.cssText = `position: fixed; max-width: 260px; box-sizing: border-box; background: white; color: black; padding: 10px 14px; border-radius: 16px; font-size: 14px; box-shadow: 0 4px 10px rgba(0,0,0,0.3); display: none; z-index: 9998; font-family: sans-serif; word-wrap: break-word; margin: 0 10px;`;
        document.body.appendChild(bubble);

        function repositionBubble() {
            if (!btn || !bubble) return;
            const btnRect = btn.getBoundingClientRect();
            const windowWidth = window.innerWidth;
            const windowHeight = window.innerHeight;
            const gap = 15;
            const isTopHalf = btnRect.top < (windowHeight / 2);
            const isLeftHalf = btnRect.left < (windowWidth / 2);
            bubble.style.left = "auto"; bubble.style.right = "auto"; bubble.style.top = "auto"; bubble.style.bottom = "auto";

            if (isLeftHalf) {
                bubble.style.left = btnRect.left + "px";
            } else {
                bubble.style.right = (windowWidth - btnRect.right) + "px";
            }
            if (isTopHalf) {
                bubble.style.top = (btnRect.bottom + gap) + "px";
            } else {
                bubble.style.bottom = (windowHeight - btnRect.top + gap) + "px";
            }
        }

        function showBubble(text, duration = 2500) {
            bubble.textContent = text;
            repositionBubble();
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
            if(["aktiviert", "bereit", "okay", "ja?", "erledigt"].some(word => spoken.includes(word))) return;

            const wake = wakewords.find(w => new RegExp(`\\b${w}\\b`, "i").test(spoken));

            if (wake && !isWaitingForCommand) {
                isWaitingForCommand = true;
                btn.style.color = COLOR_READY; 
                updateWaveAnimation();
                showBubble("🤖 Ja?");
                try { recognition.stop(); } catch(e){}

                clearTimeout(commandTimeout);

                speak("Ja?", () => { 
                    setTimeout(() => {
                        try { recognition.start(); } catch(e){} 
                        clearTimeout(commandTimeout);
                        commandTimeout = setTimeout(() => {
                            if(isWaitingForCommand && !isUserSpeaking){
                                isWaitingForCommand = false;
                                try { recognition.stop(); } catch(e){}
                                btn.style.color = isJamesActive ? COLOR_IDLE : COLOR_OFF;
                                updateWaveAnimation();
                                showBubble("⏳ Abgebrochen");
                            }
                        }, 10000);
                    }, 600);
                });
                return;
            }

            if(isWaitingForCommand && !isSpeaking){
                clearTimeout(commandTimeout); 
                isWaitingForCommand = false;
                btn.style.color = COLOR_IDLE;
                updateWaveAnimation();
                sendAction(spoken);
                return;
            }

            if(isHolding && !isSpeaking) sendAction(spoken);
        }

        function sendAction(cmd) {
            showBubble("🎤 " + cmd);
            try { recognition.stop(); } catch(e){}

            let clientId = $("body").attr("fw_id") || "no_fw_id";
            const fhemCmd = `setreading global STT_output ${cmd} [${clientId}]`;
            FW_cmd(FW_root + "?cmd=" + encodeURIComponent(fhemCmd) + "&XHR=1");
            
            speak("Erledigt!", () => {
                if (isJamesActive) {
                    setTimeout(() => {
                        try { recognition.start(); } catch(e){}
                    }, 600);
                }
            });
        }

        if(SpeechRecognition){
            recognition = new SpeechRecognition();
            recognition.lang = "de-DE";
            recognition.continuous = true;
            recognition.interimResults = false;

            recognition.onspeechstart = () => {
                isUserSpeaking = true;
                clearTimeout(commandTimeout); 
            };

            recognition.onspeechend = () => {
                isUserSpeaking = false;
                if (isWaitingForCommand && isUserSpeaking) {
                    clearTimeout(commandTimeout);
                    commandTimeout = setTimeout(() => {
                        if (isWaitingForCommand && !isUserSpeaking) {
                            isWaitingForCommand = false;
                            try { recognition.stop(); } catch(e){}
                            btn.style.color = isJamesActive ? COLOR_IDLE : COLOR_OFF;
                            updateWaveAnimation();
                            showBubble("⏳ Abgebrochen");
                        }
                    }, 3000); 
                }
            };

            recognition.onresult = (e) => {
                if (!isMobile && isSpeaking) return;
                const res = e.results[e.results.length-1];
                if(res.isFinal) processSpeech(res[0].transcript);
            }

            recognition.onend = () => {
                if(isSpeaking) return;
                if(isJamesActive || isHolding || isWaitingForCommand){
                    setTimeout(() => { try { recognition.start(); } catch(e){} }, 300);
                }
            }
        }

        const dragStart = (e) => {
            isDragging = false;
            const clientX = e.touches ? e.touches[0].clientX : e.clientX;
            const clientY = e.touches ? e.touches[0].clientY : e.clientY;
            
            startX = clientX;
            startY = clientY;
            offsetButtonX = clientX - btn.getBoundingClientRect().left;
            offsetButtonY = clientY - btn.getBoundingClientRect().top;

            if (!isDragging) { handleDown(e); }

            document.addEventListener('mousemove', dragMove, { passive: false });
            document.addEventListener('touchmove', dragMove, { passive: false });
            document.addEventListener('mouseup', dragEnd);
            document.addEventListener('touchend', dragEnd);
        };

        const dragMove = (e) => {
            const clientX = e.touches ? e.touches[0].clientX : e.clientX;
            const clientY = e.touches ? e.touches[0].clientY : e.clientY;
            const moveX = Math.abs(clientX - startX);
            const moveY = Math.abs(clientY - startY);

            if (!isDragging && (moveX > DRAG_THRESHOLD || moveY > DRAG_THRESHOLD)) {
                isDragging = true;
                if (pressTimer) { clearTimeout(pressTimer); pressTimer = null; }
            }

            if (isDragging) {
                e.preventDefault(); 
                let x = clientX - offsetButtonX;
                let y = clientY - offsetButtonY;
                x = Math.max(0, Math.min(x, window.innerWidth - 60));
                y = Math.max(0, Math.min(y, window.innerHeight - 50));
                btn.style.left = x + "px";
                btn.style.top = y + "px";
                repositionBubble();
            }
        };

        const dragEnd = (e) => {
            document.removeEventListener('mousemove', dragMove);
            document.removeEventListener('touchmove', dragMove);
            document.removeEventListener('mouseup', dragEnd);
            document.removeEventListener('touchend', dragEnd);

            if (!isDragging) {
                if (e.type === 'touchend') e.preventDefault();
                handleUp(e);
            } else {
                localStorage.setItem("jamesBtnLeft", btn.style.left);
                localStorage.setItem("jamesBtnTop", btn.style.top);
                repositionBubble();
            }
        };

        const handleDown = (e) => {
            if(!audioUnlocked){ speak(" "); audioUnlocked = true; }
            pressTimer = setTimeout(() => {
                pressTimer = null;
                isHolding = true;
                btn.style.color = "#f1c40f";
                updateWaveAnimation();
                showBubble("🎤 Höre...");
                try { recognition.start(); } catch(e){}
            }, 450);
        }

        const handleUp = (e) => {
            if(pressTimer){
                clearTimeout(pressTimer);
                pressTimer = null;
                isJamesActive = !isJamesActive;
                btn.style.color = isJamesActive ? COLOR_IDLE : COLOR_OFF;
                updateWaveAnimation();
                if(isJamesActive){
                    if (!isMobile) {
                        startupBlock = true;
                        setTimeout(() => { startupBlock = false; }, 3000);
                    }
                    showBubble("🤖 Aktiv", 2000);
                    speak("Sprachsteuerung aktiviert");
                }else{
                    isWaitingForCommand = false;
                    showBubble("😴 Aus", 2000);
                    speak("Sprachsteuerung deaktiviert"); 
                }
                if(isJamesActive){
                    try { recognition.start(); } catch(e){}
                }else{
                    try { recognition.stop(); } catch(e){}
                }
            }else if(isHolding){
                isHolding = false; 
                btn.style.color = isJamesActive ? COLOR_IDLE : COLOR_OFF;
                updateWaveAnimation(); 
                setTimeout(()=>{ 
                    if(!isJamesActive) try { recognition.stop(); } catch(e){} 
                }, 800);
            }
        }

        btn.addEventListener("mousedown", dragStart);
        btn.addEventListener("touchstart", dragStart, {passive:true});
        btn.addEventListener('contextmenu', (e) => e.preventDefault());

        registerVoiceWidget();
    }

    if(document.readyState==="complete") init();
    else window.addEventListener("load", init);
})();