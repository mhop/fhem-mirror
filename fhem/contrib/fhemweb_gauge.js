FW_version["fhemweb_gauge.js"] = "$Id: fhemweb_gauge.js 1.6.2 schwatter $";
FW_widgets['gauge'] = { createFn: window.controlGaugeVCreate };

function controlGaugeVCreate(elName, devName, vArr, currVal, set, params, cmd) {
    const dev = devName || 'unknown';

    $(`td[informid="${dev}"]`).remove();

    const parentDialog = $('#FW_okDialog').closest('.ui-dialog-content');
    if (parentDialog.length) return null;

    $(`td[informid="${dev}-${elName}"]`).remove();

    // Basis-Parameter auslesen
    const targetReading  = (Array.isArray(vArr) && vArr.length > 1) ? vArr[1] : "current_value";
    const displayUnit    = (Array.isArray(vArr) && vArr.length > 2) ? vArr[2] : "";
    const minVal         = (Array.isArray(vArr) && vArr.length > 3) ? parseFloat(vArr[3]) : 0;
    const maxVal         = (Array.isArray(vArr) && vArr.length > 4) ? parseFloat(vArr[4]) : 10000;
    const scaleFactor    = (Array.isArray(vArr) && vArr.length > 6) ? parseFloat(vArr[6]) : 1.0;

    // Farbmodus und Alarmgrenzen ermitteln
    let colorMode = "static"; 
    let colorRules = [];
    let defaultColor = "#ff9800";
    let hueStart = 0, hueEnd = 120;
    
    // Alarm-Grenzwerte
    let alarmMin = -999999;
    let alarmMax = 999999;

    if (Array.isArray(vArr) && vArr.length > 5) {
        const firstParam = vArr[5];
        if (typeof firstParam === 'string' && firstParam.startsWith('hue:')) {
            colorMode = "hue";
            let parts = firstParam.split(':');
            hueStart = parts.length > 1 ? parseInt(parts[1], 10) : 0;
            hueEnd = parts.length > 2 ? parseInt(parts[2], 10) : 120;
            
            // ANPASSUNG: Erkennt "none" und setzt den Grenzwert außer Kraft
            if (parts.length > 3) {
                let p3 = parts[3].trim().toLowerCase();
                alarmMin = (p3 === "none" || p3 === "-") ? -999999 : parseFloat(p3);
            }
            if (parts.length > 4) {
                let p4 = parts[4].trim().toLowerCase();
                alarmMax = (p4 === "none" || p4 === "-") ? 999999 : parseFloat(p4);
            }
            
        } else if (typeof firstParam === 'string' && firstParam.includes(':')) {
            colorMode = "steps";
            for (let i = 5; i < vArr.length; i++) {
                let parts = vArr[i].split(':');
                if (parts.length === 2) {
                    colorRules.push({
                        to: parseFloat(parts[0]),
                        color: parts[1].trim()
                    });
                }
            }
            colorRules.sort((a, b) => a.to - b.to);
            if (colorRules.length > 0) defaultColor = colorRules[0].color;
        } else {
            defaultColor = firstParam;
        }
    }

    const tempElement = $('<div class="room" style="display:none; position:absolute;"></div>').appendTo('body');
    let skinTextColor = tempElement.css('color') || 'inherit';
    tempElement.remove();

    // Styles injizieren
    if (!$('#gauge-widget-style').length) {
        $('<style id="gauge-widget-style">')
        .prop('type', 'text/css')
        .html(`
            /* Pulsier-Animation für die Kurve */
            @keyframes gauge-curve-pulse {
                0% { opacity: 1; }
                50% { opacity: 0.2; }
                100% { opacity: 1; }
            }

            .gauge-card {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                padding: ${5 * scaleFactor}px 0 !important;
                font-family: -apple-system, sans-serif !important;
                width: ${120 * scaleFactor}px !important;
                display: flex !important; flex-direction: column !important;
                align-items: center !important;
                box-sizing: border-box !important;
                position: relative !important;
            }

            .gauge-container {
                width: ${120 * scaleFactor}px !important;
                height: ${70 * scaleFactor}px !important;
                position: relative !important;
            }
            .gauge-svg {
                width: 100% !important;
                height: 100% !important;
                overflow: visible !important;
            }
            
            .gauge-progress {
                transition: stroke-dashoffset 0.5s ease-in-out, stroke 0.3s ease !important;
                transform-origin: center;
            }
            
            .gauge-card.gauge-trigger-pulse .gauge-progress {
                animation: gauge-curve-pulse 1.2s infinite ease-in-out !important;
            }

            .gauge-info {
                position: absolute !important;
                left: 0 !important; right: 0 !important;
                bottom: ${-12 * scaleFactor}px !important;
                text-align: center !important;
                width: 100% !important;
                pointer-events: none !important;
                display: flex !important; flex-direction: column !important;
                align-items: center !important;
            }
            .gauge-val {
                font-size: ${20 * scaleFactor}px !important;
                font-weight: bold !important;
            }
            
            /* GEÄNDERT: Transparenz für die Unit entfernt */
            .gauge-unit {
                font-size: ${13 * scaleFactor}px !important;
            }
            
            .gauge-minmax {
                font-size: ${9 * scaleFactor}px !important;
                width: ${120 * scaleFactor}px !important; /* Breite des Containers */
                display: flex !important;
                justify-content: space-between !important;
                box-sizing: border-box !important;
                margin-top: ${-2 * scaleFactor}px !important;
            }
            .gauge-minmax span:first-child {
                width: ${25 * scaleFactor}px !important;
                text-align: center !important;
                margin-left: ${-3 * scaleFactor}px !important;
            }
            .gauge-minmax span:last-child {
                width: ${25 * scaleFactor}px !important;
                text-align: center !important;
                margin-right: ${-3 * scaleFactor}px !important;
            }
        `)
        .appendTo('head');
    }

    const wrapper = $('<div/>', {
        id: dev + "_" + elName + "_gauge_wrapper",
        class: 'gauge-card gauge_widget_container',
        informid: dev + '-' + elName + '-state'
    });

    wrapper.on('click', function(e) { e.stopPropagation(); });

    const gaugeContainer = $('<div/>', { class: 'gauge-container' }).appendTo(wrapper);

    const svgHtml = `
        <svg class="gauge-svg" viewBox="0 0 120 70">
            <path d="M 10 60 A 50 50 0 0 1 110 60" fill="none" stroke="rgba(120,120,120,0.2)" stroke-width="10" stroke-linecap="round"/>
            <path class="gauge-progress" d="M 10 60 A 50 50 0 0 1 110 60" fill="none" stroke="${colorMode === 'hue' ? 'hsl(' + hueStart + ', 85%, 45%)' : defaultColor}" stroke-width="10" stroke-linecap="round" stroke-dasharray="157.08" stroke-dashoffset="157.08"/>
        </svg>
    `;
    gaugeContainer.html(svgHtml);

    const infoDiv = $('<div/>', { class: 'gauge-info' }).appendTo(gaugeContainer);
    const valDisplay = $('<div/>', { class: 'gauge-val', text: minVal }).appendTo(infoDiv);

    $('<div/>', { class: 'gauge-unit', text: displayUnit }).css('color', skinTextColor).appendTo(infoDiv);
    $('<div/>', { 
        class: 'gauge-minmax', 
        html: `<span>${minVal}</span><span>${maxVal}</span>` 
    }).css('color', skinTextColor).appendTo(wrapper);

    function updateVisualGauge(value) {
        let val = parseFloat(value);
        if (isNaN(val)) val = minVal;
        
        const clampedVal = Math.min(Math.max(val, minVal), maxVal);
        const percent = (clampedVal - minVal) / (maxVal - minVal);
        const maxArcLength = 157.08;
        const offset = maxArcLength - (percent * maxArcLength);

        const progressElement = wrapper.find('.gauge-progress');
        progressElement.css('stroke-dashoffset', offset);
        valDisplay.text(val % 1 === 0 ? val : val.toFixed(1));

        let calculatedColor = defaultColor;

        if (colorMode === "hue") {
            const currentHue = hueStart + (percent * (hueEnd - hueStart));
            calculatedColor = `hsl(${currentHue}, 85%, 45%)`;
        } else if (colorMode === "steps" && colorRules.length > 0) {
            for (let rule of colorRules) {
                if (val <= rule.to) {
                    calculatedColor = rule.color;
                    break;
                }
            }
            if (val > colorRules[colorRules.length - 1].to) {
                calculatedColor = colorRules[colorRules.length - 1].color;
            }
        }
        
        progressElement.css('stroke', calculatedColor);
        valDisplay.css('color', calculatedColor);

        // Alarm-Trigger
        if (val <= alarmMin || val >= alarmMax) {
            wrapper.addClass('gauge-trigger-pulse');
        } else {
            wrapper.removeClass('gauge-trigger-pulse');
        }
    }

    const informId = `${dev}-${targetReading}`;
    let hiddenUpdateDiv = document.getElementById(informId);
    if (!hiddenUpdateDiv) {
        hiddenUpdateDiv = document.createElement('div');
        hiddenUpdateDiv.id = informId;
        hiddenUpdateDiv.style.display = 'none';
        hiddenUpdateDiv.setAttribute('informId', informId);
        hiddenUpdateDiv.setValueFn = function(newValue) {
            updateVisualGauge(newValue);
        };
        wrapper.append(hiddenUpdateDiv);
    }

    // Erstbefüllung
    FW_queryValue(`{ReadingsVal("${dev}","${targetReading}","${minVal}")}`, {
        setValueFn: function(val) {
            updateVisualGauge(val);
        }
    });

    return wrapper[0];
}