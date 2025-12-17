FW_version["fhemweb_iconAnimated.js"] = "$Id: fhemweb_iconAnimated.js 0.8.0 schwatter $";
FW_widgets['iconAnimated'] = { createFn: iconAnimatedCreate };

function iconAnimatedCreate(elName, devName, vArr, currVal, set, params, cmd) {

    const dev = devName || 'unknown';
    const tr  = $(`tr.devname_${dev}`);
    if (!tr.length) return null;

    const col1 = tr.find('td:first-child .col1 a');
    if (!col1.length) return null;

    if (col1.data('animatedsvg')) return null;
    col1.data('animatedsvg', true);

    // ---------------------------
    // Parameter
    // ---------------------------
    const readingMap = {
        reading: vArr[1] || "state",
        stateOn:  (vArr[2]||"").split("@")[0] || "on",
        colorOn:  (vArr[2]||"").split("@")[1] || "#00ff00",
        stateOff: (vArr[3]||"").split("@")[0] || "off",
        colorOff: (vArr[3]||"").split("@")[1] || "#666",
        animationType: vArr[4] || "pulse"
    };

    // ---------------------------
    // Icongröße
    // ---------------------------
    let iconSizePx = 40; // Standardgröße 40px
    vArr.forEach(v => {
        if (v.startsWith("size@")) {
            const px = parseInt(v.split("@")[1]);
            if (!isNaN(px)) iconSizePx = px;
        }
    });

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

    // ---------------------------
    // Animation CSS
    // ---------------------------
    const styleId = 'animatedIconAnimations';
    if (!document.getElementById(styleId)) {
        const style = document.createElement('style');
        style.id = styleId;
        style.textContent = `
            @keyframes alarmAnim{0%{transform:scale(1) rotate(0)}10%{transform:scale(1.1) rotate(5deg)}20%{transform:scale(1.1) rotate(-5deg)}30%{transform:scale(1.15) rotate(5deg)}40%{transform:scale(1.15) rotate(-5deg)}50%{transform:scale(1.2) rotate(0)}100%{transform:scale(1) rotate(0)}}
            @keyframes alarmBlink{0%,100%{opacity:1}50%{opacity:.4}}
            @keyframes flowAnim {0%{transform:translateY(0)}50%{transform:translateY(3px)}100%{transform:translateY(0)}}
            @keyframes pulseAnim {0%{transform:scale(1);}50%{transform:scale(1.2);}100%{transform:scale(1);} }
            @keyframes heatFull{0%{transform:scale(1) translateY(0) skewY(0deg);opacity:1;fill:#ffb74d}20%{transform:scale(1.05) translateY(-1px) skewY(2deg);opacity:.8;fill:#ff8a65}40%{transform:scale(1.1) translateY(-2px) skewY(-2deg);opacity:.9;fill:#e53935}60%{transform:scale(1.05) translateY(-1px) skewY(1deg);opacity:.85;fill:#ff8a65}80%{transform:scale(1.1) translateY(-2px) skewY(-1deg);opacity:.9;fill:#e53935}100%{transform:scale(1) translateY(0) skewY(0deg);opacity:1;fill:#ffb74d}}
            @keyframes heatDevice{0%{transform:scale(1) translateY(0);fill:#ffb74d;opacity:1}25%{transform:scale(1.05) translateY(-1px);fill:#ffcc80;opacity:.9}50%{transform:scale(1.1) translateY(-2px);fill:#ff8a65;opacity:.85}75%{transform:scale(1.05) translateY(-1px);fill:#ffcc80;opacity:.9}100%{transform:scale(1) translateY(0);fill:#ffb74d;opacity:1}}
            @keyframes ringAnim{0%{transform:rotate(0) translateY(0)}10%{transform:rotate(10deg) translateY(1px)}20%{transform:rotate(-10deg) translateY(2px)}30%{transform:rotate(8deg) translateY(1px)}40%{transform:rotate(-8deg) translateY(2px)}50%{transform:rotate(5deg) translateY(1px)}60%,100%{transform:rotate(0) translateY(0)}}
            @keyframes robotAnim{
              0%{transform:rotate(0deg)}
              10%{transform:rotate(90deg)}
              20%{transform:rotate(180deg)}
              30%{transform:rotate(180deg)}
              40%{transform:rotate(135deg)}
              50%{transform:rotate(180deg)}
              60%{transform:rotate(180deg)}
              70%{transform:rotate(0deg)}
              80%{transform:rotate(45deg)}
              90%{transform:rotate(0deg)}
              100%{transform:rotate(0deg)}
            }
            @keyframes rotateAnimLeft {0%{transform:rotate(0deg);}100%{transform:rotate(-360deg);} }
            @keyframes rotateAnimRight {0%{transform:rotate(0deg);}100%{transform:rotate(360deg);} }
            @keyframes rotate2dAnim {0%{transform:rotateY(0deg);}100%{transform:rotateY(360deg);} }
            @keyframes bounceAnim {0%,100%{transform:translateY(0);}50%{transform:translateY(2px);} }
            @keyframes shakeAnim {0%,100%{transform:translateX(0);}25%{transform:translateX(-2px);}75%{transform:translateX(2px);} }
            @keyframes swingAnim {0%{transform:rotate(-10deg)}50%{transform:rotate(10deg)}100%{transform:rotate(-10deg)}}

            .animatedIconAlarm{animation:alarmAnim .8s ease-in-out infinite;transform-origin:center;}
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
            }
        });

        gEl.className.baseVal = '';
        if (isOn) {
            gEl.classList.add({
                alarm:'animatedIconAlarm',
                blink:'animatedIconAlarmBlink',
                flow:'animatedIconFlow',
                heat:'animatedIconHeat',
                pulse:'animatedIconPulse',
                ring:'animatedIconRing',
                robot:'animatedIconRobot',
                rotateLeft:'animatedIconRotateLeft',
                rotateRight:'animatedIconRotateRight',
                rotate2d:'animatedIconRotate2d',
                bounce:'animatedIconBounce',
                shake:'animatedIconShake',
                swing:'animatedIconSwing'
            }[readingMap.animationType] || '');
        }
    }

    // ---------------------------
    // SVG ? zentrieren + DataURL
    // ---------------------------
    function processSvg(svgText) {
        const tmp = document.createElement('div');
        tmp.innerHTML = svgText;

        svgEl = tmp.querySelector('svg');
        if (!svgEl) return;

        sanitizeSVG(svgEl);

        // Inhalte in <g> und zentrieren
        const viewBox = svgEl.getAttribute('viewBox').split(/\s+/).map(parseFloat);
        const [x, y, w, h] = viewBox;
        gEl = document.createElementNS("http://www.w3.org/2000/svg","g");
        while (svgEl.firstChild) gEl.appendChild(svgEl.firstChild);
        svgEl.appendChild(gEl);

        // transformOrigin auf Mittelpunkt setzen
        gEl.style.transformOrigin = '50% 50%';
        // optional: in die Mitte verschieben falls ViewBox nicht 0 0
        const translateX = w/2 - (x + w/2);
        const translateY = h/2 - (y + h/2);
        gEl.setAttribute('transform', `translate(${translateX},${translateY})`);

        // Klasse hinzufügen für den CSS-Hack
        svgEl.classList.add('icon', 'animatedIconForcedSize');

        // Einmalig dynamisches <style>-Tag erstellen, falls noch nicht vorhanden
        if (!document.getElementById('forcedIconSize')) {
            const style = document.createElement('style');
            style.id = 'forcedIconSize';
            style.textContent = `
                /* Höchste Spezifität wie Skin-Hack */
                #content svg.icon, 
                #content img.icon, 
                svg.icon.animatedIconForcedSize, 
                img.icon.animatedIconForcedSize {
                    width: ${iconSizePx}px !important;
                    height: ${iconSizePx}px !important;
                    max-width: ${iconSizePx}px !important;
                    max-height: ${iconSizePx}px !important;
                }
            `;
            document.head.appendChild(style);
        }

        col1.find('svg.icon').remove();
        col1.prepend(svgEl);
        col1.prepend(document.createTextNode(' '));

        FW_queryValue(`{ReadingsVal("${dev}","${readingMap.reading}","")}`, {
            setValueFn: val => updateState(val)
        });
    }

    // ---------------------------
    // SVG laden (animatedSVG ? icon)
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

// ---------------------------
// SVG Sanitizer
// ---------------------------
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
