FW_version["fhemweb_iconAnimated.js"] = "$Id: fhemweb_iconAnimated.js 0.8.5 schwatter $";
FW_widgets['iconAnimated'] = { createFn: iconAnimatedCreate };

function iconAnimatedCreate(elName, devName, vArr, currVal, set, params, cmd) {

    const dev = devName || 'unknown';
    const tr  = $(`tr.devname_${dev}`);
    if (!tr.length) return null;

    // --- Schutz gegen Dialog-Container ---
    const parentDialog = $('#FW_okDialog').closest('.ui-dialog-content');
    if (parentDialog.length) {
        return null;
    }

    const col1 = tr.find('td:first-child .col1 a');
    if (!col1.length) return null;

    if (col1.data('animatedsvg')) return null;
    col1.data('animatedsvg', true);

    // ---------------------------
    // Parameter & Effekt-Parsing
    // ---------------------------
    const rawAnim = vArr[4] || "pulse";
    const animMain = rawAnim.split('@')[0];
    const animExtra = rawAnim.split('@')[1] || "";

    const readingMap = {
        reading: vArr[1] || "state",
        stateOn:  (vArr[2]||"").split("@")[0] || "on",
        colorOn:  (vArr[2]||"").split("@")[1] || "#00ff00",
        stateOff: (vArr[3]||"").split("@")[0] || "off",
        colorOff: (vArr[3]||"").split("@")[1] || "#666",
        animationType: animMain,
        extraEffect: animExtra
    };

    // ---------------------------
    // Icongröße
    // ---------------------------
    let iconSizePx = 40;
    vArr.forEach(v => {
        if (v.startsWith("size@")) {
            const px = parseInt(v.split("@")[1]);
            if (!isNaN(px)) iconSizePx = px;
        }
    });

    // --- Platzhalter-ID generieren ---
    const placeholderId = `placeholder_${dev.replace(/[^a-zA-Z0-9_-]/g,'_')}`;

    // ---------------------------
    // Select ausblenden
    // ---------------------------
    const hideAnimatedSvgSelect = () => {
        $('select.select_widget').each(function() {
            const $sel = $(this);
            if ($sel.find('option[value="iconAnimated"]').length > 0 && !$sel.data('hidden')) {
                $sel.hide().data('hidden', true);
                const $td = $sel.closest('td');
                if ($td.length) $td.hide();
            }
        });
    };
    hideAnimatedSvgSelect();
    new MutationObserver(hideAnimatedSvgSelect)
        .observe(document.body, { childList:true, subtree:true });

    // --- Platzhalter mit relativer Position für Effekt-Layer ---
    col1.find('svg.icon, img').remove(); 
    const placeholder = $(`<div id="${placeholderId}" style="display:inline-block; width:${iconSizePx}px; height:${iconSizePx}px; vertical-align:middle; margin-right:4px; position:relative;"></div>`);
    col1.prepend(placeholder);

    // ---------------------------
    // Animation CSS
    // ---------------------------
    const styleId = 'animatedIconAnimations';
    if (!document.getElementById(styleId)) {
        const style = document.createElement('style');
        style.id = styleId;
        style.textContent = `
            @keyframes alarmAnim{0%{transform:scale(1) rotate(0)}10%{transform:scale(1.1) rotate(5deg)}20%{transform:scale(1.1) rotate(-5deg)}30%{transform:scale(1.15) rotate(5deg)}40%{transform:scale(1.15) rotate(-5deg)}50%{transform:scale(1.2) rotate(0)}100%{transform:scale(1) rotate(0)}}
            @keyframes alarmGlow {0% { filter: blur(4px) drop-shadow(0 0 10px var(--glow-color)); opacity: 0; transform: scale(0.9);} 50% { filter: blur(6px) drop-shadow(0 0 30px var(--glow-color)) drop-shadow(0 0 50px var(--glow-color)); opacity: 1; transform: scale(1.15); } 100% { filter: blur(4px) drop-shadow(0 0 10px var(--glow-color)); opacity: 0; transform: scale(0.9); } }
            @keyframes ringSpread{0%{transform:scale(1);opacity:1.0;stroke-width:3}100%{transform:scale(2.2);opacity:0;stroke-width:3}}
            @keyframes alarmBlink{0%,100%{opacity:1}50%{opacity:.4}}
            @keyframes flowAnim {0%{transform:translateY(0)}50%{transform:translateY(3px)}100%{transform:translateY(0)}}
            @keyframes pulseAnim {0%{transform:scale(1);}50%{transform:scale(1.2);}100%{transform:scale(1);} }
            @keyframes heatFull{0%{transform:scale(1) translateY(0) skewY(0deg);opacity:1;fill:#ffb74d}20%{transform:scale(1.05) translateY(-1px) skewY(2deg);opacity:.8;fill:#ff8a65}40%{transform:scale(1.1) translateY(-2px) skewY(-2deg);opacity:.9;fill:#e53935}60%{transform:scale(1.05) translateY(-1px) skewY(1deg);opacity:.85;fill:#ff8a65}80%{transform:scale(1.1) translateY(-2px) skewY(-1deg);opacity:.9;fill:#e53935}100%{transform:scale(1) translateY(0) skewY(0deg);opacity:1;fill:#ffb74d}}
            @keyframes heatDevice{0%{transform:scale(1) translateY(0);fill:#ffb74d;opacity:1}25%{transform:scale(1.05) translateY(-1px);fill:#ffcc80;opacity:.9}50%{transform:scale(1.1) translateY(-2px);fill:#ff8a65;opacity:.85}75%{transform:scale(1.05) translateY(-1px);fill:#ffcc80;opacity:.9}100%{transform:scale(1) translateY(0);fill:#ffb74d;opacity:1}}
            @keyframes ringAnim{0%{transform:rotate(0) translateY(0)}10%{transform:rotate(10deg) translateY(1px)}20%{transform:rotate(-10deg) translateY(2px)}30%{transform:rotate(8deg) translateY(1px)}40%{transform:rotate(-8deg) translateY(2px)}50%{transform:rotate(5deg) translateY(1px)}60%,100%{transform:rotate(0) translateY(0)}}
            @keyframes robotAnim{0%{transform:rotate(0deg)}10%{transform:rotate(90deg)}20%{transform:rotate(180deg)}30%{transform:rotate(180deg)}40%{transform:rotate(135deg)}50%{transform:rotate(180deg)}60%{transform:rotate(180deg)}70%{transform:rotate(0deg)}80%{transform:rotate(45deg)}90%{transform:rotate(0deg)}100%{transform:rotate(0deg)}}
            @keyframes rotateAnimLeft {0%{transform:rotate(0deg);}100%{transform:rotate(-360deg);} }
            @keyframes rotateAnimRight {0%{transform:rotate(0deg);}100%{transform:rotate(360deg);} }
            @keyframes rotate2dAnim {0%{transform:rotateY(0deg);}100%{transform:rotateY(360deg);} }
            @keyframes bounceAnim {0%,100%{transform:translateY(0);}50%{transform:translateY(2px);} }
            @keyframes shakeAnim {0%,100%{transform:translateX(0);}25%{transform:translateX(-2px);}75%{transform:translateX(2px);} }
            @keyframes swingAnim {0%{transform:rotate(-10deg)}50%{transform:rotate(10deg)}100%{transform:rotate(-10deg)}}

            .animatedIconAlarm{animation:alarmAnim .8s ease-in-out infinite;transform-origin:center;}
            .effect-glow {animation: alarmGlow .8s ease-in-out infinite !important; transform-origin: center center;}
            [id^="placeholder_"] {
                display: inline-flex !important;
                align-items: center;
                justify-content: center;
            }
            [id^="placeholder_"] svg.icon {
                position: relative;
                z-index: 2;
                margin: 0 !important; /* Verhindert Versatz durch Standard-Margeneinstellungen */
            }
            .animatedIconAlarmBlink{animation:alarmBlink 1.0s linear infinite;}
            .animatedIconFlow { animation: flowAnim 1.5s ease-in-out infinite; transform-origin:center;}
            .animatedIconHeat{animation:heatFull 1.5s ease-in-out infinite;transform-origin:bottom center}
            .animatedIconHeatDevice{animation:heatDevice 1.5s ease-in-out infinite;transform-origin:center}
            .animatedIconPulse { animation:pulseAnim 1s infinite ease-in-out; transform-origin:center; }
            .animatedIconRing{animation:ringAnim .8s ease-in-out infinite;transform-origin:50% 0%}
            .animatedIconRobot{animation:robotAnim 10s ease-in-out infinite;transform-origin:50% 50%;}
            .animatedIconRotateLeft { animation:rotateAnimLeft 2s linear infinite; transform-origin:center; }
            .animatedIconRotateRight { animation:rotateAnimRight 2s linear infinite; transform-origin:center; }
            .animatedIconRotate2d { animation:rotate2dAnim 3s linear infinite; transform-origin:center; }
            .animatedIconBounce { animation:bounceAnim 0.5s ease-in-out infinite; transform-origin:center; }
            .animatedIconShake { animation:shakeAnim 0.5s ease-in-out infinite; transform-origin:center; }
            .animatedIconSwing { animation: swingAnim 2s ease-in-out infinite; transform-origin:top center;}
            .ring-container {
                position: absolute;
                top: 50%;
                left: 50%;
                width: 100%;
                height: 100%;
                transform: translate(-50%, -50%); /* Zentriert den Container */
                display: flex;
                align-items: center;
                justify-content: center;
                pointer-events: none;
                overflow: visible;
            }
            .ring{fill:none;transform-origin:center;opacity:0}
            .ring1{animation:ringSpread 2s ease-out infinite}
            .ring2{animation:ringSpread 2s ease-out infinite 0.6s}
        `;
        document.head.appendChild(style);
    }

    let svgEl = null;
    let gEl   = null;

    // ---------------------------
    // State Update
    // ---------------------------
    function updateState(val) {
        if (!svgEl || !gEl) return;

        const valStr = String(val).trim();
        const num = valStr.match(/-?\d+(\.\d+)?/);
        const numVal = num ? parseFloat(num[0]) : null;

        let isOn = false;
        if (readingMap.stateOn.startsWith(">=") && numVal !== null) {
            isOn = numVal >= parseFloat(readingMap.stateOn.slice(2));
        } else {
            isOn = valStr === readingMap.stateOn;
        }

        if (readingMap.stateOff.startsWith("<") && numVal !== null) {
            if (numVal < parseFloat(readingMap.stateOff.slice(1))) isOn = false;
        } else if (valStr === readingMap.stateOff) {
            isOn = false;
        }

        const color = isOn ? readingMap.colorOn : readingMap.colorOff;

        svgEl.querySelectorAll('*').forEach(el => {
            if (el.tagName.match(/path|circle|rect|polygon|ellipse|line|polyline/i)) {
                el.setAttribute('fill', color);
                el.setAttribute('stroke', 'none');
            }
        });

        // Reset Klassen und Effekte
        gEl.className.baseVal = '';
        const ph = document.getElementById(placeholderId);
        if(ph) ph.querySelectorAll('.ring-container, .glow-container').forEach(r => r.remove());

        if (isOn) {
            const baseClass = {
                alarm:'animatedIconAlarm',
                blink:'animatedIconAlarmBlink',
                flow:'animatedIconFlow',
                heat:'animatedIconHeat',
                heatDevice: 'animatedIconHeatDevice',
                pulse:'animatedIconPulse',
                ring:'animatedIconRing',
                robot:'animatedIconRobot',
                rotateLeft:'animatedIconRotateLeft',
                rotateRight:'animatedIconRotateRight',
                rotate2d:'animatedIconRotate2d',
                bounce:'animatedIconBounce',
                shake:'animatedIconShake',
                swing:'animatedIconSwing'
            }[readingMap.animationType] || '';

            gEl.classList.add(baseClass);

            if (readingMap.extraEffect === 'glow' && ph) {
                // 1. Glow Container mit z-index: 1 erstellen
                const glow = $(`
                    <div class="glow-container" style="position:absolute; top:50%; left:50%; width:100%; height:100%; z-index:1; transform:translate(-50%, -50%); display:flex; align-items:center; justify-content:center; pointer-events:none;">
                        <svg viewBox="0 0 100 100" style="width:140%; height:140%; overflow:visible; --glow-color:${color};">
                            <defs>
                                <radialGradient id="grad1" cx="50%" cy="50%" r="50%">
                                    <stop offset="20%" style="stop-color:var(--glow-color); stop-opacity:0.8" />
                                    <stop offset="100%" style="stop-color:var(--glow-color); stop-opacity:0" />
                                </radialGradient>
                            </defs>
                            <circle cx="50" cy="50" r="45" fill="url(#grad1)" class="effect-glow" />
                        </svg>
                    </div>`);

                // 2. Das eigentliche Icon-SVG auf z-index: 2 setzen, damit es VOR dem Glow liegt
                if (svgEl) {
                    svgEl.style.position = "relative";
                    svgEl.style.zIndex = "2";
                }
                
                // 3. Glow VORNE im DOM einfügen (prepend), damit es unter dem Icon liegt
                $(ph).prepend(glow);
            }

            if (readingMap.extraEffect === 'rings' && ph) {
                // 1. Icon nach vorne holen
                if (svgEl) {
                    svgEl.style.position = "relative";
                    svgEl.style.zIndex = "2";
                }

                // 2. Ringe erstellen (mit transform-center Logik)
                const rings = $(`
                    <div class="ring-container" style="z-index:1;">
                        <svg viewBox="0 0 100 100" style="width:100%; height:100%; overflow:visible;">
                            <circle class="ring ring1" cx="50" cy="50" r="40" stroke="${color}" fill="none" />
                            <circle class="ring ring2" cx="50" cy="50" r="40" stroke="${color}" fill="none" />
                        </svg>
                    </div>`);
                
                // Wir nutzen prepend, damit sie unter dem Icon liegen (wegen z-index)
                $(ph).prepend(rings);
            }
        }
    }

    // ---------------------------
    // SVG zentrieren + DataURL
    // ---------------------------
    function processSvg(svgText) {
        const tmp = document.createElement('div');
        tmp.innerHTML = svgText;

        svgEl = tmp.querySelector('svg');
        if (!svgEl) return;

        sanitizeSVG(svgEl);

        const viewBox = svgEl.getAttribute('viewBox').split(/\s+/).map(parseFloat);
        const [x, y, w, h] = viewBox;
        gEl = document.createElementNS("http://www.w3.org/2000/svg","g");
        while (svgEl.firstChild) gEl.appendChild(svgEl.firstChild);
        svgEl.appendChild(gEl);

        gEl.style.transformOrigin = '50% 50%';

        const iconClass = 'animatedIcon_' + dev.replace(/[^a-zA-Z0-9_-]/g,'_');
        svgEl.classList.add('icon', iconClass);

        const styleId = 'forcedIconSize_' + iconClass;
        if (!document.getElementById(styleId)) {
            const style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
                svg.${iconClass},
                img.${iconClass} {
                    width: ${iconSizePx}px !important;
                    height: ${iconSizePx}px !important;
                    max-width: ${iconSizePx}px !important;
                    max-height: ${iconSizePx}px !important;
                    overflow: visible !important;
                }
            `;
            document.head.appendChild(style);
        }

        const ph = document.getElementById(placeholderId);
        if(ph) {
            ph.innerHTML = "";
            ph.appendChild(svgEl);
        } else {
            col1.prepend(svgEl);
        }

        FW_queryValue(`{ReadingsVal("${dev}","${readingMap.reading}","")}`, {
            setValueFn: val => updateState(val)
        });
    }

    // ---------------------------
    // SVG laden
    // ---------------------------
    FW_queryValue(`{AttrVal("${dev}","iconAnimated","")}`, {
        setValueFn: v => {
            if (v && v.startsWith("data:image/svg+xml")) {
                processSvg(decodeURIComponent(v.split(",")[1]));
                return;
            }

            FW_queryValue(`{AttrVal("${dev}","icon","")}`, {
                setValueFn: iconName => {
                    if (!iconName) return;
                    const cmd = `{FW_makeImage("${iconName}","","")}`;
                    FW_cmd(FW_root + '?cmd=' + encodeURIComponent(cmd) + '&XHR=1', data => {
                        if (!data) return;
                        processSvg(data);
                    });
                }
            });
        }
    });

    const informer = $('<div/>', {
        informid: dev + '-' + readingMap.reading,
        style: 'display:none'
    });
    informer[0].setValueFn = val => updateState(val);
    tr.append(informer);

    return null;
}

function sanitizeSVG(root) {
    ['width','height','style'].forEach(a => root.removeAttribute(a));
    root.querySelectorAll('*').forEach(el => {
        ['width','height'].forEach(a => el.removeAttribute(a));
    });
    if (!root.hasAttribute('viewBox')) {
        root.setAttribute('viewBox','0 0 24 24');
    }
    root.setAttribute('preserveAspectRatio','xMidYMid meet');
}