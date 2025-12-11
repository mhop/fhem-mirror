FW_version["fhemweb_animatedsvg.js"] = "$Id: fhemweb_animatedsvg.js 0.6.0 $";
FW_widgets['animatedsvg'] = { createFn: animatedSvgCreate };

function animatedSvgCreate(elName, devName, vArr, currVal, set, params, cmd) {
    const dev = devName || 'unknown';
    if ($(`div.animatedsvg_widget[informid="${dev}-state"]`).length) return null;
    $(`td[informid="${dev}"]`).remove();

    const tr = $(`tr.devname_${dev}`);

    // ---------------------------
    // Wrappergröße aus size@XXX oder default
    // ---------------------------
    let widgetSize = 40; // Default
    vArr.forEach(v => {
        if (v.startsWith("size@")) {
            const val = parseInt(v.split("@")[1]);
            if (!isNaN(val)) widgetSize = val;
        }
    });

    const wrapper = $('<div/>', {
        class: 'animatedsvg_widget',
        informid: dev + '-state',
        style: `display:block; width:${widgetSize}px; height:${widgetSize}px; overflow:visible;`
    });

    tr.find('td:first-child').css({ width: '5%' });
    tr.find('td:last').css({ width: 'auto', height: 'auto' });

    // ---------------------------
    // Parameter
    // ---------------------------
    const readingMap = {
        reading: vArr[1] || "state",
        stateOn: (vArr[2]||"").split("@")[0] || "on",
        colorOn: (vArr[2]||"").split("@")[1] || "#00ff00",
        stateOff: (vArr[3]||"").split("@")[0] || "off",
        colorOff: (vArr[3]||"").split("@")[1] || "#666",
        animationType: vArr[4] || "pulse"
    };

    let svgEl = null, gEl = null;

    // ---------------------------
    // Animationen CSS
    // ---------------------------
    const styleId = 'animatedIconAnimations';
    if (!document.getElementById(styleId)) {
        const style = document.createElement('style');
        style.id = styleId;
        style.textContent = `
            @keyframes pulseAnim {0%{transform:scale(1);}50%{transform:scale(1.2);}100%{transform:scale(1);} }
            @keyframes rotateAnimLeft {0%{transform:rotate(0deg);}100%{transform:rotate(-360deg);} }
            @keyframes rotateAnimRight {0%{transform:rotate(0deg);}100%{transform:rotate(360deg);} }
            @keyframes rotate2dAnim {0%{transform:rotateY(0deg);}25%{transform:rotateY(90deg);}50%{transform:rotateY(180deg);}
                                     75%{transform:rotateY(270deg);}100%{transform:rotateY(360deg);} }
            @keyframes bounceAnim {0%,100%{transform:translateY(0);}50%{transform:translateY(2px);} }
            @keyframes shakeAnim {0%,100%{transform:translateX(0);}25%{transform:translateX(-2px);}75%{transform:translateX(2px);} }
            .animatedIconPulse {animation:pulseAnim 1s infinite ease-in-out; transform-origin:center;}
            .animatedIconRotateLeft {animation:rotateAnimLeft 2s linear infinite; transform-origin:center;}
            .animatedIconRotateRight {animation:rotateAnimRight 2s linear infinite; transform-origin:center;}
            .animatedIconRotate2d {animation:rotate2dAnim 4s linear infinite; transform-origin:center;}
            .animatedIconBounce {animation:bounceAnim 0.5s ease-in-out infinite; transform-origin:center;}
            .animatedIconShake {animation:shakeAnim 0.5s ease-in-out infinite; transform-origin:center;}
        `;
        document.head.appendChild(style);
    }

    // ---------------------------
    // State Update
    // ---------------------------
    function updateState(val) {
        if (!svgEl || !gEl) return;
        const color = val === readingMap.stateOn ? readingMap.colorOn : readingMap.colorOff;

        svgEl.querySelectorAll('*').forEach(el => {
            if (el.tagName.match(/path|circle|rect|polygon|ellipse|line|polyline/i)) {
                el.setAttribute('fill', color);
            }
        });

        gEl.classList.remove(
            'animatedIconPulse','animatedIconRotateLeft','animatedIconRotateRight','animatedIconRotate2d',
            'animatedIconBounce','animatedIconShake'
        );

        if (val === readingMap.stateOn) {
            gEl.classList.add({
                pulse: "animatedIconPulse",
                rotateLeft: "animatedIconRotateLeft",
                rotateRight: "animatedIconRotateRight",
                rotate2d: "animatedIconRotate2d",
                bounce: "animatedIconBounce",
                shake: "animatedIconShake"
            }[readingMap.animationType] || "");
        }
    }

    // ---------------------------
    // SVG Load
    // ---------------------------
    FW_queryValue(`{AttrVal("${dev}","animatedSVG","")}`, {
        setValueFn: v => {
            if (!v || !v.startsWith("data:image/svg+xml")) return;

            wrapper.empty();
            const svgData = decodeURIComponent(v.split(",")[1]);
            const tmp = document.createElementNS('http://www.w3.org/2000/svg','svg');
            tmp.innerHTML = svgData;

            svgEl = tmp.querySelector('svg') || tmp;
            sanitizeSVG(svgEl);

            gEl = document.createElementNS("http://www.w3.org/2000/svg","g");
            while(svgEl.firstChild) gEl.appendChild(svgEl.firstChild);
            svgEl.appendChild(gEl);

            gEl.setAttribute("transform-origin", "50% 50%");

            svgEl.style.width = "100%";
            svgEl.style.height = "100%";
            svgEl.style.display = "block";

            wrapper[0].appendChild(svgEl);

            FW_queryValue(`{ReadingsVal("${dev}","${readingMap.reading}","")}`, {
                setValueFn: val => updateState(val)
            });
        }
    });

    wrapper[0].setValueFn = val => updateState(val);
    tr.find('td:last').append(wrapper);
    return wrapper[0];
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
