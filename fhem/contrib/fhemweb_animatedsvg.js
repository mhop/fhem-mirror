FW_version["fhemweb_animatedsvg.js"] = "$Id: fhemweb_animatedsvg.js 0.7.6 schwatter $";
FW_widgets['animatedsvg'] = { createFn: animatedSvgCreate };

function animatedSvgCreate(elName, devName, vArr, currVal, set, params, cmd) {

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
    let iconSizeEm = 1.3;
    vArr.forEach(v => {
        if (v.startsWith("size@")) {
            const px = parseInt(v.split("@")[1]);
            if (!isNaN(px)) iconSizeEm = px / 16;
        }
    });

        
    // Select ausblenden
    const hideAnimatedSvgSelect = () => {
        $('select.select_widget').each(function() {
            const $sel = $(this);
            if ($sel.find('option[value="animatedsvg"]').length > 0 && !$sel.data('hidden')) {
                $sel.hide();
                $sel.data('hidden', true);
                // leeren TD ebenfalls ausblenden
                const $td = $sel.closest('td');
                if ($td.length) {
                    $td.hide();
                }
            }
        });
    };
    // einmal sofort versuchen
    hideAnimatedSvgSelect();
    // MutationObserver auf <body>, falls select später hinzugefügt wird
    const observer = new MutationObserver(hideAnimatedSvgSelect);
    observer.observe(document.body, { childList: true, subtree: true });

    // ---------------------------
    // Animation CSS
    // ---------------------------
    const styleId = 'animatedIconAnimations';
    if (!document.getElementById(styleId)) {
        const style = document.createElement('style');
        style.id = styleId;
        style.textContent = `
            @keyframes pulseAnim {0%{transform:scale(1);}50%{transform:scale(1.2);}100%{transform:scale(1);} }
            @keyframes rotateAnimLeft {0%{transform:rotate(0deg);}100%{transform:rotate(-360deg);} }
            @keyframes rotateAnimRight {0%{transform:rotate(0deg);}100%{transform:rotate(360deg);} }
            @keyframes rotate2dAnim {0%{transform:rotateY(0deg);}100%{transform:rotateY(360deg);} }
            @keyframes bounceAnim {0%,100%{transform:translateY(0);}50%{transform:translateY(2px);} }
            @keyframes shakeAnim {0%,100%{transform:translateX(0);}25%{transform:translateX(-2px);}75%{transform:translateX(2px);} }

            .animatedIconPulse { animation:pulseAnim 1s infinite ease-in-out; transform-origin:center; }
            .animatedIconRotateLeft { animation:rotateAnimLeft 2s linear infinite; transform-origin:center; }
            .animatedIconRotateRight { animation:rotateAnimRight 2s linear infinite; transform-origin:center; }
            .animatedIconRotate2d { animation:rotate2dAnim 3s linear infinite; transform-origin:center; }
            .animatedIconBounce { animation:bounceAnim 0.5s ease-in-out infinite; transform-origin:center; }
            .animatedIconShake { animation:shakeAnim 0.5s ease-in-out infinite; transform-origin:center; }
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

        let isOn = false;

        // val sicher in String + Zahl wandeln
        const valStr = String(val).trim();
        const numMatch = valStr.match(/-?\d+(\.\d+)?/);
        const numVal = numMatch ? parseFloat(numMatch[0]) : null;

        if (readingMap.stateOn.startsWith(">=") && numVal !== null) {
            const limit = parseFloat(readingMap.stateOn.slice(2));
            if (!isNaN(limit)) {
                isOn = numVal >= limit;
            }
        } else {
            isOn = (valStr === readingMap.stateOn);
        }

        if (readingMap.stateOff.startsWith("<") && numVal !== null) {
            const limit = parseFloat(readingMap.stateOff.slice(1));
            if (!isNaN(limit) && numVal < limit) {
                isOn = false;
            }
        } else if (valStr === readingMap.stateOff) {
            isOn = false;
        }

        const color = isOn ? readingMap.colorOn : readingMap.colorOff;

        svgEl.querySelectorAll('*').forEach(el => {
            if (el.tagName.match(/path|circle|rect|polygon|ellipse|line|polyline/i)) {
                el.setAttribute('fill', color);
            }
        });

        gEl.classList.remove(
            'animatedIconPulse','animatedIconRotateLeft','animatedIconRotateRight',
            'animatedIconRotate2d','animatedIconBounce','animatedIconShake'
        );

        if (isOn) {
            gEl.classList.add({
                pulse: 'animatedIconPulse',
                rotateLeft: 'animatedIconRotateLeft',
                rotateRight: 'animatedIconRotateRight',
                rotate2d: 'animatedIconRotate2d',
                bounce: 'animatedIconBounce',
                shake: 'animatedIconShake',
            }[readingMap.animationType] || '');
        }
    }

    // ---------------------------
    // SVG laden & Icon ersetzen
    // ---------------------------
    FW_queryValue(`{AttrVal("${dev}","animatedSVG","")}`, {
        setValueFn: v => {
            if (!v || !v.startsWith("data:image/svg+xml")) return;

            const svgData = decodeURIComponent(v.split(",")[1]);
            const tmp = document.createElement('div');
            tmp.innerHTML = svgData;

            svgEl = tmp.querySelector('svg');
            if (!svgEl) return;

            sanitizeSVG(svgEl);

            svgEl.classList.add('icon');
            svgEl.style.width  = iconSizeEm + 'em';
            svgEl.style.height = iconSizeEm + 'em';
            svgEl.style.verticalAlign = 'middle';

            gEl = document.createElementNS("http://www.w3.org/2000/svg","g");
            while (svgEl.firstChild) gEl.appendChild(svgEl.firstChild);
            svgEl.appendChild(gEl);

            col1.find('svg.icon').remove();
            col1.prepend(svgEl);
            col1.prepend(document.createTextNode(' '));

            FW_queryValue(`{ReadingsVal("${dev}","${readingMap.reading}","")}`, {
                setValueFn: val => updateState(val)
            });

        }
    });

    // ---------------------------
    // InformID für Live-Updates
    // ---------------------------
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
    root.style.removeProperty('width');
    root.style.removeProperty('height');

    root.querySelectorAll('*').forEach(el => {
        ['width','height'].forEach(a => el.removeAttribute(a));
        if (el.hasAttribute('style')) {
            const cleaned = el.getAttribute('style')
                .split(';')
                .filter(s => !/^\s*(width|height)\s*:/i.test(s))
                .join(';');
            cleaned ? el.setAttribute('style', cleaned) : el.removeAttribute('style');
        }
    });

    if (!root.hasAttribute('viewBox')) {
        root.setAttribute('viewBox','0 0 24 24');
    }

    root.setAttribute('preserveAspectRatio','xMidYMid meet');
}
