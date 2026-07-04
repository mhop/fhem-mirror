FW_version["fhemweb_multigauge.js"] = "$Id: fhemweb_multigauge.js 0.7.1 schwatter $";
FW_widgets['multigauge'] = { createFn: window.controlMultiGaugeVCreate };

console.log("GAUGE-WIDGET: 3-Fach Multi-Gauge (Isoliert und Konfliktfrei) geladen!");

function controlMultiGaugeVCreate(elName, devName, vArr, currVal, set, params, cmd) {
    const dev = devName || 'unknown';

    $(`td[informid="${dev}"]`).remove();
    const parentDialog = $('#FW_okDialog').closest('.ui-dialog-content');
    if (parentDialog.length) return null;
    $(`td[informid="${dev}-${elName}"]`).remove();

    function parseParamBlock(paramStr) {
        if (!paramStr || paramStr === "-" || paramStr === "none") return null;
        let parts = paramStr.split(':');
        
        let minVal = 0, maxVal = 100;
        let alarmMin = -999999, alarmMax = 999999;
        
        if (parts[3] && parts[3].includes('-')) {
            let limits = parts[3].split('-');
            minVal = parseFloat(limits[0]);
            maxVal = parseFloat(limits[1]);
            if (limits.length > 2) alarmMin = parseFloat(limits[2]);
            if (limits.length > 3) alarmMax = parseFloat(limits[3]);
        }

        let colorStr = parts[2] ? parts[2].trim() : "#ff9800";
        let isHue = colorStr.startsWith('hue-');
        let hueStart = 0, hueEnd = 120;
        if (isHue) {
            let hParts = colorStr.split('-');
            let startVal = parseInt(hParts[1], 10);
            hueStart = isNaN(startVal) ? 0 : startVal;
            let endVal = parseInt(hParts[2], 10);
            hueEnd = isNaN(endVal) ? 120 : endVal;
        }

        return {
            reading: parts[0] ? parts[0].trim() : null,
            unit: parts[1] ? parts[1].trim() : "",
            color: colorStr,
            isHue: isHue,
            hueStart: hueStart,
            hueEnd: hueEnd,
            min: minVal,
            max: maxVal,
            alarmMin: alarmMin,
            alarmMax: alarmMax
        };
    }

    const r1 = parseParamBlock(vArr[1]);
    const r2 = parseParamBlock(vArr[2]);
    const r3 = parseParamBlock(vArr[3]);
    const labelText = vArr[4] ? vArr[4].trim() : "";
    const scaleFactor = vArr[5] ? parseFloat(vArr[5]) : 1.0; 

    // Eindeutige Klasse für diesen Scale-Faktor generieren
    const scopeClass = 'mg-scope-' + scaleFactor.toString().replace('.', '-');

    if (!$('#' + scopeClass).length) {
        $('<style id="' + scopeClass + '">')
        .prop('type', 'text/css')
        .html(`
            @keyframes mg-curve-pulse {
                0% { opacity: 1; }
                50% { opacity: 0.2; }
                100% { opacity: 1; }
            }
            .${scopeClass} .mg-card {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                padding: 0 !important;
                font-family: -apple-system, sans-serif !important;
                width: ${160 * scaleFactor}px !important;
                height: ${135 * scaleFactor}px !important;
                display: flex !important;
                flex-direction: column !important;
                align-items: center !important;
                box-sizing: border-box !important;
                overflow: hidden !important;
            }
            .${scopeClass} .mg-container {
                width: ${160 * scaleFactor}px !important;
                height: ${135 * scaleFactor}px !important;
                position: relative !important;
            }
            .${scopeClass} .mg-svg {
                width: 100% !important;
                height: 100% !important;
                display: block !important;
            }
            .mg-progress {
                transition: stroke-dashoffset 0.5s ease-in-out, stroke 0.3s ease !important;
            }
            .${scopeClass}.mg-alarm-t1 .mg-t1 { animation: mg-curve-pulse 1.2s infinite ease-in-out !important; }
            .${scopeClass}.mg-alarm-t2 .mg-t2 { animation: mg-curve-pulse 1.2s infinite ease-in-out !important; }
            .${scopeClass}.mg-alarm-t3 .mg-t3 { animation: mg-curve-pulse 1.2s infinite ease-in-out !important; }
            .${scopeClass} .mg-info {
                position: absolute !important;
                left: 0; right: 0; 
                top: ${35 * scaleFactor}px !important; 
                margin: auto !important;
                width: 100% !important;
                height: ${75 * scaleFactor}px !important;
                pointer-events: none !important;
                display: flex !important;
                flex-direction: column !important;
                align-items: center !important;
                justify-content: center !important; 
            }
            .${scopeClass} .mg-label { 
                position: absolute !important;
                top: ${80 * scaleFactor}px !important; 
                font-size: ${11 * scaleFactor}px !important; 
                font-weight: bold; 
                color: currentColor; 
                opacity: 0.7;
            }
            .${scopeClass} .mg-values-stack {
                display: flex;
                flex-direction: column;
                align-items: center;
                line-height: 1.30;
            }
            .${scopeClass} .mg-vrow {
                font-weight: bold !important;
                text-align: center !important;
                width: 100% !important;
                transition: color 0.3s ease;
            }
            .${scopeClass} .mg-vrow.mg-size-large  { font-size: ${24 * scaleFactor}px !important; }
            .${scopeClass} .mg-vrow.mg-size-medium { font-size: ${17 * scaleFactor}px !important; }
            .${scopeClass} .mg-vrow.mg-size-small  { font-size: ${13 * scaleFactor}px !important; }
        `)
        .appendTo('head');
    }

    const wrapper = $('<div/>', { id: dev + "_" + elName + "_multigauge_wrapper", class: 'mg-card gauge_widget_container ' + scopeClass });
    wrapper.on('click', function(e) { e.stopPropagation(); });
    const gaugeContainer = $('<div/>', { class: 'mg-container' }).appendTo(wrapper);

    let svgHtml = `<svg class="mg-svg" viewBox="0 0 160 135">`;
    
    if (r1) {
        svgHtml += `
        <path d="M 34.06 125.94 A 65 65 0 1 1 125.94 125.94" fill="none" stroke="rgba(120,120,120,0.12)" stroke-width="5" stroke-linecap="butt"/>
        <path class="mg-progress mg-t1" d="M 34.06 125.94 A 65 65 0 1 1 125.94 125.94" fill="none" stroke="${r1.isHue ? 'clear' : r1.color}" stroke-width="5.2" stroke-linecap="butt" stroke-dasharray="306.31" stroke-dashoffset="306.31"/>`;
    }
    if (r2) {
        svgHtml += `
        <path d="M 37.57 122.43 A 60 60 0 1 1 122.43 122.43" fill="none" stroke="rgba(120,120,120,0.12)" stroke-width="5" stroke-linecap="butt"/>
        <path class="mg-progress mg-t2" d="M 37.57 122.43 A 60 60 0 1 1 122.43 122.43" fill="none" stroke="${r2.isHue ? 'clear' : r2.color}" stroke-width="5.2" stroke-linecap="butt" stroke-dasharray="282.74" stroke-dashoffset="282.74"/>`;
    }
    if (r3) {
        svgHtml += `
        <path d="M 41.10 118.90 A 55 55 0 1 1 118.90 118.90" fill="none" stroke="rgba(120,120,120,0.12)" stroke-width="5" stroke-linecap="butt"/>
        <path class="mg-progress mg-t3" d="M 41.10 118.90 A 55 55 0 1 1 118.90 118.90" fill="none" stroke="${r3.isHue ? 'clear' : r3.color}" stroke-width="5.2" stroke-linecap="butt" stroke-dasharray="259.18" stroke-dashoffset="259.18"/>`;
    }
    svgHtml += `</svg>`;
    gaugeContainer.html(svgHtml);

    const infoDiv = $('<div/>', { class: 'mg-info' }).appendTo(gaugeContainer);
    const valStack = $('<div/>', { class: 'mg-values-stack' }).appendTo(infoDiv);

    let d1, d2, d3;
    let activeRings = [r1, r2, r3].filter(Boolean).length;

    if (activeRings === 3) {
        if (r1) d1 = $('<div/>', { class: 'mg-vrow mg-size-small' }).appendTo(valStack);
        if (r2) d2 = $('<div/>', { class: 'mg-vrow mg-size-large' }).appendTo(valStack);
        if (r3) d3 = $('<div/>', { class: 'mg-vrow mg-size-small' }).appendTo(valStack);
    } else if (activeRings === 2) {
        let targets = [];
        targets.push($('<div/>', { class: 'mg-vrow mg-size-large' }).appendTo(valStack));
        targets.push($('<div/>', { class: 'mg-vrow mg-size-medium' }).appendTo(valStack));
        
        let idx = 0;
        if (r1) { d1 = targets[idx++]; }
        if (r2) { d2 = targets[idx++]; }
        if (r3) { d3 = targets[idx++]; }
    } else {
        let target = $('<div/>', { class: 'mg-vrow mg-size-large' }).appendTo(valStack);
        if (r1) d1 = target;
        if (r2) d2 = target;
        if (r3) d3 = target;
    }
    
    if (labelText) {
        $('<div/>', { class: 'mg-label', text: labelText }).appendTo(infoDiv);
    }

    function processTrackUpdate(rConfig, trackClass, displayDiv, val, baseLen, alarmClass) {
        let targetTrack = wrapper.find('.' + trackClass);
        if (!targetTrack.length) return;

        let pct = Math.min(Math.max((val - rConfig.min) / (rConfig.max - rConfig.min), 0), 1);
        targetTrack.css('stroke-dashoffset', baseLen - (pct * baseLen));
        
        let finalColor = rConfig.color;
        if (rConfig.isHue) {
            let currentHue = rConfig.hueStart + (pct * (rConfig.hueEnd - rConfig.hueStart));
            finalColor = `hsl(${currentHue}, 85%, 45%)`;
        }
        targetTrack.css('stroke', finalColor);

        if (displayDiv && displayDiv.length) {
            displayDiv.css('color', finalColor);
            displayDiv.text(`${val % 1 === 0 ? val : val.toFixed(1)} ${rConfig.unit}`);
        }

        let currentNum = parseFloat(val);
        if (isNaN(currentNum)) currentNum = rConfig.min;

        if (currentNum <= rConfig.alarmMin || currentNum >= rConfig.alarmMax) {
            wrapper.addClass(alarmClass);
        } else {
            wrapper.removeClass(alarmClass);
        }
    }

    if (r1) {
        let id = `${dev}-${r1.reading}`;
        let div = document.getElementById(id) || document.createElement('div');
        div.id = id; div.style.display = 'none'; div.setAttribute('informId', id);
        div.setValueFn = function(v) { processTrackUpdate(r1, 'mg-t1', d1, parseFloat(v), 306.31, 'mg-alarm-t1'); };
        wrapper.append(div);
        FW_queryValue(`{ReadingsVal("${dev}","${r1.reading}","${r1.min}")}`, { setValueFn: div.setValueFn });
    }
    if (r2) {
        let id = `${dev}-${r2.reading}`;
        let div = document.getElementById(id) || document.createElement('div');
        div.id = id; div.style.display = 'none'; div.setAttribute('informId', id);
        div.setValueFn = function(v) { processTrackUpdate(r2, 'mg-t2', d2, parseFloat(v), 282.74, 'mg-alarm-t2'); };
        wrapper.append(div);
        FW_queryValue(`{ReadingsVal("${dev}","${r2.reading}","${r2.min}")}`, { setValueFn: div.setValueFn });
    }
    if (r3) {
        let id = `${dev}-${r3.reading}`;
        let div = document.getElementById(id) || document.createElement('div');
        div.id = id; div.style.display = 'none'; div.setAttribute('informId', id);
        div.setValueFn = function(v) { processTrackUpdate(r3, 'mg-t3', d3, parseFloat(v), 259.18, 'mg-alarm-t3'); };
        wrapper.append(div);
        FW_queryValue(`{ReadingsVal("${dev}","${r3.reading}","${r3.min}")}`, { setValueFn: div.setValueFn });
    }

    return wrapper[0];
}