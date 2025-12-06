FW_version["fhemweb_controlminidash.js"] = "$Id: controlminidash.js 0.2.6 schwatter $";
FW_widgets['controlminidash'] = { createFn: controlMiniDashCreate };

function controlMiniDashCreate(elName, devName, vArr, currVal, set, params, cmd) {
    const dev = devName || 'unknown';

    // --- Schutz: nur ein Widget pro Device ---
    if ($(`div.controlminidash_widget[informid="${dev}-state"]`).length) {
        return null;
    }

    $(`td[informid="${dev}"]`).remove();

    const tr = $(`tr.devname_${dev}`);
    const tdCol1 = tr.find('td:first-child');
    const tdCol3 = tr.find('td:nth-child(2)');

    tdCol1.css({
        width: '25%',
    });

    const wrapperWidth = 355;
    const wrapperHeight = 160;

    const wrapper = $('<div/>', {
        class: 'controlminidash_widget',
        informid: dev + '-state',
        style: `display:block !important; width:${wrapperWidth}px; height:${wrapperHeight}px; display:inline-block !important; overflow:visible !important; text-align:left !important; padding:0 !important; float:left !important; margin:0 !important;`
    });

    const svgNS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("id", "controlminidash");
    svg.setAttribute("viewBox", `0 0 ${wrapperWidth} ${wrapperHeight}`);
    svg.setAttribute("width", wrapperWidth);
    svg.setAttribute("height", wrapperHeight);
    svg.setAttribute("style", `width:${wrapperWidth}px !important; height:${wrapperHeight}px !important; text-align:left !important; padding:0 !important; float:left !important; margin:0 !important;`);
    svg.setAttribute("preserveAspectRatio", "xMinYMin meet");
    svg.classList.add("controlminidash");

    const style = document.createElementNS(svgNS, "style");
    style.textContent = `
      .button-area { cursor: pointer; opacity: 0 !important; }
      .button-placeholder, g[id$="Link"] rect { fill: transparent !important; stroke: none !important; pointer-events: all !important; }
    `;
    svg.appendChild(style);

    const icons = document.createElementNS(svgNS, "g");
    icons.setAttribute("id", "Icons");
    ["btn1Icon","btn2Icon","btn3Icon","btn4Icon","btn5Icon","btn6Icon"].forEach((id,i)=>{
        const g = document.createElementNS(svgNS,"g");
        g.setAttribute("id", id);
        const x = (i<3) ? 20 : 295;
        const y = (i%3)*50 + 10;
        g.setAttribute("transform", `translate(${x},${y})`);
        icons.appendChild(g);
    });
    svg.appendChild(icons);

    const createButtons = (start, count, xOffset) => {
        const group = document.createElementNS(svgNS,"g");
        group.setAttribute("id", start<4 ? "leftButtons":"rightButtons");
        for(let i=start;i<start+count;i++){
            const g = document.createElementNS(svgNS,"g");
            g.setAttribute("id","btn"+i);
            g.setAttribute("class","button-area");
            g.setAttribute("transform", `translate(${xOffset},${(i-start)*50+10})`);
            const rect = document.createElementNS(svgNS,"rect");
            rect.setAttribute("x","0");
            rect.setAttribute("y","0");
            rect.setAttribute("width","40");
            rect.setAttribute("height","40");
            rect.setAttribute("class","button-placeholder");
            g.appendChild(rect);
            group.appendChild(g);
            group.appendChild(document.createElementNS(svgNS,"g"));
        }
        return group;
    };
    svg.appendChild(createButtons(1,3,20));
    svg.appendChild(createButtons(4,3,295));

    const dataCircle = document.createElementNS(svgNS, "circle");
    dataCircle.setAttribute("id", "dataCircle");
    dataCircle.setAttribute("cx", "177");
    dataCircle.setAttribute("cy", "90");
    dataCircle.setAttribute("r", "70");
    dataCircle.setAttribute("fill", "none");
    dataCircle.setAttribute("stroke", "grey");
    dataCircle.setAttribute("stroke-width", "5");
    dataCircle.setAttribute("opacity", "0.4");

    const circumference = 2 * Math.PI * 70;
    const gap = 0.20 * circumference;
    dataCircle.setAttribute("stroke-dasharray", `${circumference - gap} ${gap}`);
    dataCircle.setAttribute("transform", "rotate(126,177,90)"); // öffnet unten

    svg.appendChild(dataCircle);

    const dataSegment = document.createElementNS(svgNS,"circle");
    dataSegment.setAttribute("id","dataSegment");
    dataSegment.setAttribute("cx","177");
    dataSegment.setAttribute("cy","90");
    dataSegment.setAttribute("r","75");
    dataSegment.setAttribute("fill","none");
    dataSegment.setAttribute("stroke","#FFE74B");
    dataSegment.setAttribute("stroke-width","5");
    dataSegment.style.transition = "stroke-dasharray 1s ease, stroke 1s ease";
    svg.appendChild(dataSegment);

    const internalIds = ["info1Val","info2Val","info3Val","info4Val"];
    const texts = [
        {id:"info1Val", y:70, size:28, content:""},
        {id:"info2Val", y:95, size:18, content:""},
        {id:"info3Val", y:115, size:14, content:""},
        {id:"info4Val", y:130, size:14, content:""}
    ];
    texts.forEach(t=>{
        const text = document.createElementNS(svgNS,"text");
        text.setAttribute("x","177");
        text.setAttribute("y",t.y);
        text.setAttribute("text-anchor","middle");
        //text.setAttribute("fill","white");
        text.setAttribute("fill","currentColor");
        text.classList.add("col2");
        text.setAttribute("font-family","Arial");
        text.setAttribute("font-size",t.size);
        text.setAttribute("font-weight","normal");
        const tspan = document.createElementNS(svgNS,"tspan");
        tspan.setAttribute("class","informId_ringSVG:"+t.id);
        tspan.textContent = t.content;
        text.appendChild(tspan);
        svg.appendChild(text);
    });
    wrapper[0].appendChild(svg);

    const CIRCUMFERENCE = 2 * Math.PI * 75;
    const setRing = (percent, color) => {
        dataSegment.setAttribute('stroke-dasharray', `${percent / 138 * CIRCUMFERENCE} ${CIRCUMFERENCE}`);
        dataSegment.style.stroke = color;
        dataSegment.setAttribute('transform', 'rotate(140,177,90)');
    };
    const tempToColor = (temp) => {
        temp = Math.max(7, Math.min(30, temp));
        const ratio = (temp - 7) / (30 - 7);
        const hue = 270 - ratio * 270;
        return `hsl(${hue}, 100%, 50%)`;
    };
    const updateRing = (temp) => {
        const clampedTemp = Math.max(7, Math.min(30, temp)); // Temp auf 7..30°C begrenzen
        setRing((clampedTemp-7)/(30-7)*100, tempToColor(clampedTemp));
    };
    updateRing(7);

    // --- SVG-Knob (Dial-Style) ---
    const MIN_TEMP = 7;
    const MAX_TEMP = 30;

    let currentTemp;   // noch undefiniert, wird durch measured-temp gesetzt
    let previewTemp;
    let isDragging = false;

    // Knob erstellen, Position kommt später aus FHEM
    if (!knob) {
        var knob = document.createElementNS(svgNS, "circle");
        knob.setAttribute("r", "10");
        knob.setAttribute("fill", "#fff");
        knob.setAttribute("stroke", "#555");
        knob.setAttribute("stroke-width", "2");
        knob.style.touchAction = "none";
        knob.style.visibility = "hidden";
        svg.appendChild(knob);
    }

    // --- Geometrie und Winkelkonstanten ---
    const CENTER_X = 177;
    const CENTER_Y = 90;
    const RADIUS = 75;
    const ANGLE_START = 140;
    const ANGLE_MIN = 130;
    const ANGLE_MAX = 40;
    const ANGLE_ARC = 260;

    // --- Hilfsfunktionen ---
    function roundHalf(temp) {
        //return Math.round((temp + 0.00001) * 2) / 2;
        return Math.round(temp * 2) / 2;
    }

    function roundHalfIfNeeded(val) {
        // Prüfen, ob val schon auf 0,5er-Stufe liegt
        if (val * 2 === Math.round(val * 2)) {
            return val; // schon korrekt
        }
        // sonst runden auf nächste 0,5
        return Math.round(val * 2) / 2;
    }

    function tempToAngle(temp) {
        const clamped = Math.max(MIN_TEMP, Math.min(MAX_TEMP, temp));
        const norm = (clamped - MIN_TEMP) / (MAX_TEMP - MIN_TEMP);
        return ANGLE_START + norm * ANGLE_ARC;
    }

    function angleToTemp(angleDeg) {
        let angle = (angleDeg + 360) % 360;
        if (angle > ANGLE_MAX && angle < ANGLE_MIN) {
            const distToMin = Math.abs(angle - ANGLE_MIN);
            const distToMax = Math.abs(angle - ANGLE_MAX);
            angle = distToMin < distToMax ? ANGLE_MIN : ANGLE_MAX;
        }
        let rel = angle >= ANGLE_MIN ? angle - ANGLE_MIN : (360 - ANGLE_MIN) + angle;
        const norm = rel / ANGLE_ARC;
        return MIN_TEMP + norm * (MAX_TEMP - MIN_TEMP);
    }

    function setKnobPosition(temp) {
        const angle = tempToAngle(roundHalf(temp)) * Math.PI / 180;
        const cx = CENTER_X + RADIUS * Math.cos(angle);
        const cy = CENTER_Y + RADIUS * Math.sin(angle);
        knob.setAttribute("cx", cx);
        knob.setAttribute("cy", cy);
        if (knob.style.visibility === "hidden") {
            // next frame, um sicher zu sein, dass DOM geupdated ist
            requestAnimationFrame(() => { knob.style.visibility = "visible"; });
        }
    }

    function updateInfo3Val(temp) {
        const el = svg.querySelector(`.informId_ringSVG\\:info3Val`);
        if (el) {
            const roundedTemp = roundHalf(temp);
            el.textContent = roundedTemp.toFixed(1) + "\u00B0C";
        }
    }

    function clientToAngle(clientX, clientY) {
        const pt = svg.createSVGPoint();
        pt.x = clientX; pt.y = clientY;
        const cursor = pt.matrixTransform(svg.getScreenCTM().inverse());
        const dx = cursor.x - CENTER_X;
        const dy = cursor.y - CENTER_Y;
        let angleDeg = Math.atan2(dy, dx) * 180 / Math.PI;
        if (angleDeg < 0) angleDeg += 360;
        return angleDeg;
    }

    function pageToTemp(clientX, clientY) {
        let ang = clientToAngle(clientX, clientY);
        let temp = angleToTemp(ang);
        if (temp > MAX_TEMP) temp = MAX_TEMP;
        if (temp < MIN_TEMP) temp = MIN_TEMP;
        return roundHalfIfNeeded(temp);
    }

    let dragStartTemp = 0;
    let dragStartAngle = 0;

    function normalizeAngle(a) {
        while (a > 180) a -= 360;
        while (a < -180) a += 360;
        return a;
    }

    function startDrag(evt) {
        evt.preventDefault();
        isDragging = true;
        knob.setAttribute("stroke", "#00FF88");

        const clientX = (evt.touches && evt.touches[0]) ? evt.touches[0].clientX : evt.clientX;
        const clientY = (evt.touches && evt.touches[0]) ? evt.touches[0].clientY : evt.clientY;

        dragStartTemp = currentTemp;
        dragStartAngle = clientToAngle(clientX, clientY);

        previewTemp = dragStartTemp;
        setKnobPosition(previewTemp);
        updateRing(previewTemp);
        updateInfo3Val(previewTemp);
    }

    function moveDrag(evt) {
        if (!isDragging) return;
        evt.preventDefault();

        const clientX = (evt.touches && evt.touches[0]) ? evt.touches[0].clientX : evt.clientX;
        const clientY = (evt.touches && evt.touches[0]) ? evt.touches[0].clientY : evt.clientY;

        const currentAngle = clientToAngle(clientX, clientY);

        const rawDelta = currentAngle - dragStartAngle;
        const deltaAngle = normalizeAngle(rawDelta);

        const tempDelta = (deltaAngle / ANGLE_ARC) * (MAX_TEMP - MIN_TEMP);
        previewTemp = dragStartTemp + tempDelta;

        previewTemp = Math.max(MIN_TEMP, Math.min(MAX_TEMP, previewTemp));
        previewTemp = roundHalfIfNeeded(previewTemp);

        setKnobPosition(previewTemp);
        updateRing(previewTemp);
        updateInfo3Val(previewTemp);
    }

    function sendTempToFhem(temp) {
        const targetReading = Array.isArray(vArr) && vArr.length > 3 ? vArr[3] : "desired-temp";
        const fullCmd = `{fhem("set ${dev} ${targetReading} ${temp.toFixed(1)}")}`;
        FW_cmd(FW_root + '?cmd=' + encodeURIComponent(fullCmd) + '&XHR=1');
    }

    function endDrag(evt) {
        if (!isDragging) return;
        isDragging = false;
        knob.setAttribute("stroke", "#555");

        currentTemp = roundHalf(previewTemp);
        sendTempToFhem(currentTemp);

        setKnobPosition(currentTemp);
        updateRing(currentTemp);
        updateInfo3Val(currentTemp);

        setTimeout(() => {
            FW_queryValue(`{ReadingsVal("${dev}","measured-temp","")}`, {
                setValueFn: val => {
                    const t = parseFloat(val);
                    if (!isNaN(t)) {
                        currentTemp = roundHalf(t);
                        setKnobPosition(currentTemp);
                        updateRing(currentTemp);
                    }
                }
            });
        }, 1200);
    }

    // --- Animation (optional) ---
    function animateKnobToTemp(targetTemp, duration = 800) {
        setKnobPosition(currentTemp);
        updateRing(currentTemp);

        const startTemp = currentTemp;
        const steps = Math.ceil(duration / 16);
        let i = 0;

        const animate = () => {
            i++;
            const t = i / steps;
            const easedT = t < 0.5 ? 2*t*t : -1 + (4-2*t)*t;
            const temp = startTemp + (targetTemp - startTemp) * easedT;
            setKnobPosition(temp);
            updateRing(temp);
            if (i < steps) requestAnimationFrame(animate);
        };

        animate();
    }

    // --- Startwert vom FHEM-Server laden ---
    FW_queryValue(`{ReadingsVal("${dev}","measured-temp","")}`, {
        setValueFn: val => {
            const t = parseFloat(val);
            if (!isNaN(t)) {
                currentTemp = roundHalf(t);
                previewTemp = currentTemp;
                setKnobPosition(currentTemp);
                updateRing(currentTemp);
                updateInfo3Val(currentTemp);
            }
        }
    });

    // --- Events ---
    knob.addEventListener("pointerdown", startDrag, { passive: false });
    window.addEventListener("pointermove", moveDrag, { passive: false });
    window.addEventListener("pointerup", endDrag);

    knob.addEventListener("touchstart", startDrag, { passive: false });
    window.addEventListener("touchmove", moveDrag, { passive: false });
    window.addEventListener("touchend", endDrag);

    // --- Initialwert aus FHEM ---
    if (Array.isArray(vArr) && vArr.length > 1) {
        const measuredReading = vArr[1];
        FW_queryValue(`{ReadingsVal("${dev}","${measuredReading}","")}`, {
            setValueFn: val => {
                const t = parseFloat(val);
                if (!isNaN(t)) {
                    currentTemp = roundHalf(t);
                    previewTemp = currentTemp;

                    // Animation statt direkter Positionierung
                    animateKnobToTemp(currentTemp, 1000);
                }
            }
        });
    } else {
        // Fallback: Startposition animiert setzen
        animateKnobToTemp(currentTemp, 1000);
    }

    const readingMap = {};
    if(Array.isArray(vArr)){
        for(let i=1; i<Math.min(vArr.length, internalIds.length+1); i++){
            readingMap[vArr[i]] = internalIds[i-1];
        }
    }

    Object.entries(readingMap).forEach(([reading, internalId])=>{
        const informId = `${dev}-${reading}`;
        let div = document.getElementById(informId);
        if(!div){
            div = document.createElement('div');
            div.id = informId;
            div.style.display='none';
            div.setAttribute('informId',informId);
            div.setValueFn = value=>{
                const el = svg.querySelector(`.informId_ringSVG\\:${internalId}`);
                if(el){
                    if(internalId==="info1Val" || internalId==="info3Val"){
                        el.textContent = value + "\u00B0C";
                    } else if (internalId === "info2Val") {
                        if (value === "#" || value === "" || value == null) {
                            el.textContent = "";          // Text komplett ausblenden
                        } else {
                            el.textContent = value + "\u0025";   // Zahl + % anzeigen
                        }
                    } else {
                        el.textContent = value;
                    }
                }

                // --- info3Val und info4Val nach oben verschieben, wenn info2Val leer ist ---
                const info2Text = svg.querySelector(`.informId_ringSVG\\:info2Val`);
                const info3Text = svg.querySelector(`.informId_ringSVG\\:info3Val`);
                const info4Text = svg.querySelector(`.informId_ringSVG\\:info4Val`);

                if (info2Text && info3Text && info4Text) {
                    if (!info2Text.textContent) { // info2Val leer -> nach oben verschieben
                        info3Text.parentElement.setAttribute("y", 95); // neue Y-Position
                        info4Text.parentElement.setAttribute("y", 110);
                    } else { // info2Val sichtbar -> Standardposition
                        info3Text.parentElement.setAttribute("y", 115);
                        info4Text.parentElement.setAttribute("y", 130);
                    }
                }

                if(internalId==="info1Val") {
                    const t = parseFloat(value) || 0;
                    setKnobPosition(t);
                    updateRing(t);
                }
            };
            wrapper[0].appendChild(div);
        }
        FW_queryValue(`{ReadingsVal("${dev}","${reading}","")}`, {
            setValueFn: val => div.setValueFn(val)
        });
    });

    wrapper[0].setValueFn = (value, ring) => {
        const tspan = svg.querySelector(`.informId_ringSVG\\:${ring}`);
        if (tspan) {
            if (ring === "info1Val" || ring === "info3Val") {
                tspan.textContent = value + "\u00B0C";
            } else if (ring === "info2Val") {
                if (value === "#" || value === "" || value == null) {
                    tspan.textContent = "";
                } else {
                    tspan.textContent = value + "\u0025";
                }
            } else {
                tspan.textContent = value; // Fallback für andere Felder
            }
        }

        // --- info3Val und info4Val nach oben verschieben, wenn info2Val leer ist ---
        const info2Text = svg.querySelector(`.informId_ringSVG\\:info2Val`);
        const info3Text = svg.querySelector(`.informId_ringSVG\\:info3Val`);
        const info4Text = svg.querySelector(`.informId_ringSVG\\:info4Val`);

        if (info2Text && info3Text && info4Text) {
            if (!info2Text.textContent) { // info2Val leer -> nach oben verschieben
                info3Text.parentElement.setAttribute("y", 95); // Beispielwerte
                info4Text.parentElement.setAttribute("y", 110);
            } else { // info2Val sichtbar -> Standardposition
                info3Text.parentElement.setAttribute("y", 115);
                info4Text.parentElement.setAttribute("y", 130);
            }
        }

        if (ring === "info1Val") {
            const temp = parseFloat(svg.querySelector('.informId_ringSVG\\:info1Val')?.textContent) || 0;
            updateRing(temp);
        }
    }

    window.sendFHEMCmd = (cmd, el) => {
        const baseUrl = typeof FW_root !== 'undefined' ? FW_root : '';

        // Direkt FHEM-Befehl ausführen (kein Toggle)
        if (cmd && cmd.includes('@')) {
            const parts = cmd.split('@');
            const iconName = parts[0];      // optional, bleibt für Logging oder Icons
            const statePart = parts[1] || '';

            let fullCmd = '';
            if (statePart.includes('.')) {
                // Punkt als Separator: param und value trennen
                const [param, value] = statePart.split('.');
                fullCmd = `{fhem("set ${dev} ${param} ${value}")}`;
            } else {
                // fallback, falls kein Punkt
                fullCmd = `{fhem("set ${dev} ${statePart}")}`;
            }

            FW_cmd(baseUrl + '?cmd=' + encodeURIComponent(fullCmd) + '&XHR=1');
        }
    };

    // 1?? Buttons auslesen und Reading-Werte speichern (mit Logging)
    ["btn1Cmd","btn2Cmd","btn3Cmd","btn4Cmd","btn5Cmd","btn6Cmd"].forEach(k => {
        const informId = `${dev}-${k}`;
        let div = document.createElement('div');
        div.id = informId;
        div.style.display = 'none';
        div.setAttribute('informid', informId);

        // Speichert den FHEM-Befehl direkt
        div.setValueFn = v => {
            div.textContent = v;
        };

        wrapper[0].appendChild(div);

        FW_queryValue(`{AttrVal("${dev}","${k}","")}`, { setValueFn: val => div.setValueFn(val) });
    });

    function toHexColor(cssColor) {
        if (!cssColor) return '';
        const ctx = document.createElement('canvas').getContext('2d');
        ctx.fillStyle = cssColor;
        return ctx.fillStyle; // liefert #rrggbb
    }

    ["btn1Color","btn2Color","btn3Color","btn4Color","btn5Color","btn6Color"].forEach(k => {
        const informId = `${dev}-${k}`;
        let div = document.createElement('div');
        div.id = informId;
        div.style.display = 'none';
        div.setAttribute('informid', informId);
        wrapper[0].appendChild(div);

        FW_queryValue(`{AttrVal("${dev}","${k}","")}`, {
            setValueFn: val => div.textContent = val
        });
    });
    // --- Icons vorbereiten und gleichzeitig laden ---
    const iconCache = {};

    ["btn1Icon","btn2Icon","btn3Icon","btn4Icon","btn5Icon","btn6Icon"].forEach((k, idx) => {
        const informId = `${dev}-${k}`;
        let div = document.createElement('div');
        div.id = informId;
        div.style.display = 'none';
        div.setAttribute('informid', informId);

        div.setValueFn = v => {
            const g = svg.querySelector(`#${k}`);
            if (!g) return;

            g.innerHTML = '';

            const icon_size = 35;

            // --- Button ausblenden, wenn kein Icon vorhanden ---
            const fhemIdx = 5 + idx;
            const fhemIconEntry = Array.isArray(vArr) ? vArr[fhemIdx] : null;
            const hasIcon = (v && v.startsWith('data:image/svg+xml')) || (fhemIconEntry && fhemIconEntry.includes('@'));

            const btnArea = svg.querySelector(`#btn${idx+1}`);
            if (btnArea) {
                    if (!hasIcon) {
                            btnArea.style.display = 'none';  // Button komplett ausblenden
                    } else {
                            btnArea.style.display = 'block'; // Button wieder anzeigen, falls Icon da
                    }
            }

            if (!hasIcon) return; // keine weiteren Aktionen, wenn kein Icon

            // --- Hier kommt der bisherige Code zum Rendern des Icons ---

            // --- 1. FHEM-Icon über vArr ---
            if (Array.isArray(vArr)) {
                const fhemIdx = 5 + idx;
                const fhemIconEntry = vArr[fhemIdx];
                if (fhemIconEntry && fhemIconEntry.includes('@')) {
                    const [iconName, statePart] = fhemIconEntry.split('@');
                    const colorDiv = document.getElementById(`${dev}-${k.replace('Icon','Color')}`);
                    let fill = colorDiv ? colorDiv.textContent.trim() : '';
                    fill = fill ? toHexColor(fill) : ''; // **hier Hex konvertieren**

                    const cacheKey = fill ? `${iconName}@${fill}` : iconName;
                    if (iconCache[cacheKey]) {
                        g.appendChild(iconCache[cacheKey].cloneNode(true));
                        return;
                    }

                    const cmdStr = fill
                        ? `{FW_makeImage("${iconName}@${fill}","${iconName}","")}`
                        : `{FW_makeImage("${iconName}","","")}`; // kein Fill -> Skinfarbe

                    FW_cmd(FW_root + '?cmd=' + encodeURIComponent(cmdStr) + '&XHR=1', data => {
                        if (!data) return;
                        const tmp = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
                        tmp.innerHTML = data;
                        const svgEl = tmp.querySelector('svg') || tmp;

                        let x=0, y=0, w=100, h=100;
                        const vb = svgEl.getAttribute('viewBox');
                        if (vb) {
                            const p = vb.split(/\s+/);
                            x = parseFloat(p[0]); y = parseFloat(p[1]);
                            w = parseFloat(p[2]); h = parseFloat(p[3]);
                        }

                        const scale = icon_size / Math.max(w,h);
                        const offsetX = (icon_size - w*scale)/2 - x*scale;
                        const offsetY = (icon_size - h*scale)/2 - y*scale;

                        const iconGroup = document.createElementNS('http://www.w3.org/2000/svg','g');
                        iconGroup.setAttribute('transform', `translate(${offsetX},${offsetY}) scale(${scale})`);
                        Array.from(svgEl.childNodes).forEach(c => iconGroup.appendChild(c.cloneNode(true)));
                        g.appendChild(iconGroup);
                        iconCache[cacheKey] = iconGroup.cloneNode(true);
                    });
                    return;
                }
            }

            // --- 2. DataURL direkt aus Reading ---
            if (v && v.startsWith('data:image/svg+xml')) {
                        const colorDiv = document.getElementById(`${dev}-${k.replace('Icon','Color')}`);
                        const fill = colorDiv ? colorDiv.textContent.trim() : ''; // aus btnXColor
                        const hexFill = fill ? toHexColor(fill) : '';

                        const iconSVG = decodeURIComponent(v.split(',')[1]);
                        const tmp = document.createElementNS('http://www.w3.org/2000/svg','svg');
                        tmp.innerHTML = iconSVG;
                        const svgEl = tmp.querySelector('svg') || tmp;

                        // Falls Farbe vorhanden, auf alle Pfade anwenden
                        if(hexFill){
                                    svgEl.querySelectorAll('*').forEach(el => {
                                                if(el.tagName.match(/path|circle|rect|polygon|ellipse|line|polyline/i)){
                                                            el.setAttribute('fill', hexFill);
                                                }
                                    });
                        }

                        let vb = svgEl.getAttribute('viewBox'), w=100, h=100;
                        if (vb) {
                                    const p = vb.split(/\s+/);
                                    w = parseFloat(p[2]); h = parseFloat(p[3]);
                        }

                        const scale = icon_size / Math.max(w,h);
                        const offsetX = (icon_size - w*scale)/2;
                        const offsetY = (icon_size - h*scale)/2;

                        const iconGroup = document.createElementNS('http://www.w3.org/2000/svg','g');
                        iconGroup.setAttribute('transform', `translate(${offsetX},${offsetY}) scale(${scale})`);
                        Array.from(svgEl.childNodes).forEach(c => iconGroup.appendChild(c.cloneNode(true)));
                        g.appendChild(iconGroup);
            }
        }
        wrapper[0].appendChild(div);
        FW_queryValue(`{AttrVal("${dev}","${k}","")}`, { setValueFn: val => div.setValueFn(val) });
    });

    // 2?? Klick-Handler für die Buttons (vArr zuerst, dann Reading, mit Logging)
    svg.querySelectorAll('.button-area').forEach(btn => {
        btn.addEventListener('click', () => {
            const btnNum = parseInt(btn.id.replace("btn",""));
            let handled = false;

            // --- Animation direkt beim Klick ---
            const rect = btn.getBoundingClientRect();

            const wave = document.createElement('div');
            wave.style.position = 'fixed';
            wave.style.left = rect.left + 'px';
            wave.style.top = rect.top + 'px';
            wave.style.width = rect.width + 'px';
            wave.style.height = rect.height + 'px';
            wave.style.borderRadius = '50%';
            wave.style.background = 'rgba(0,255,0,0.7)';
            wave.style.pointerEvents = 'none';
            wave.style.transform = 'scale(0)';
            wave.style.transition = 'transform 0.4s ease-out, opacity 0.4s ease-out';
            wave.style.zIndex = 9999;

            document.body.appendChild(wave);

            requestAnimationFrame(() => {
                wave.style.transform = 'scale(3)';
                wave.style.opacity = '0';
            });

            setTimeout(() => wave.remove(), 400);

            // Prüfen ob vArr einen FHEM-Befehl enthält
            if (Array.isArray(vArr)) {
                const val = vArr[4 + btnNum]; // Offset im vArr
                if (val && val.includes('@')) {
                    sendFHEMCmd(val, btn);
                    handled = true;
                } else {
                    console.log(`   ? No valid vArr entry for btn${btnNum}:`, val);
                }
            }

            // Falls kein val aus vArr, btnXCmd auslesen
            if (!handled) {
                const cmdDiv = document.getElementById(`${dev}-btn${btnNum}Cmd`);
                const cmdText = cmdDiv?.textContent?.trim() || '';

                if (cmdText) {

                    let fullCmd = '';
                    if (cmdText.startsWith('{') && cmdText.endsWith('}')) {
                        fullCmd = cmdText;
                    } else if (/^(set|get|attr|deleteattr)\b/i.test(cmdText)) {
                        fullCmd = `{fhem("${cmdText}")}`;
                    } else {
                        fullCmd = `{fhem("set ${dev} ${cmdText}")}`;
                    }

                    FW_cmd(FW_root + '?cmd=' + encodeURIComponent(fullCmd) + '&XHR=1');
                    handled = true;
                } else {
                    console.log(`   ? No command in btn${btnNum}Cmd`);
                }
            }
        });
    });

    return wrapper[0];
}

/*
=pod

=begin html

  <li>controlminidash,&lt;measured-temp&gt;,&lt;humidity&gt;,&lt;desired-temp&gt;,&lt;info&gt;,
      &lt;btn1&gt;,&lt;btn2&gt;,&lt;btn3&gt;,&lt;btn4&gt;,&lt;btn5&gt;,&lt;btn6&gt;
      - create a compact mini dashboard for a device<br>
      see <a href='https://wiki.fhem.de/wiki/FHEMWEB/ControlMiniDash'>FHEMWEB/ControlMiniDash</a> for documentation and examples.</li><br>

=end html

=cut
*/
