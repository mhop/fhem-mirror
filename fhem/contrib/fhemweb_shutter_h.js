FW_version["fhemweb_shutter_h.js"] = "$Id: fhemweb_shutter_h.js 0.8.0 schwatter $";
FW_widgets['shutter_h'] = { createFn: window.controlShutterHCreate };

function controlShutterHCreate(elName, devName, vArr, currVal, set, params, cmd) {
    const dev = devName || 'unknown';

    if ($(`div.shutter_h_widget_container[informid="${dev}-shutter-h-state"]`).length) {
        return null;
    }

    const parentDialog = $('#FW_okDialog').closest('.ui-dialog-content');
    if (parentDialog.length) return null;

    $(`td[informid="${dev}"]`).remove();

    // Dynamische Ermittlung aus dem widgetOverride Array (vArr)
    const targetSetCmd = (Array.isArray(vArr) && vArr.length > 2) ? vArr[1] : "target_position";
    const readingPosition  = (Array.isArray(vArr) && vArr.length > 3) ? vArr[2] : "current_position";
    const readingUp  = (Array.isArray(vArr) && vArr.length > 3) ? vArr[3] : "up";
    const readingDown  = (Array.isArray(vArr) && vArr.length > 3) ? vArr[4] : "down";
    const readingStop  = (Array.isArray(vArr) && vArr.length > 3) ? vArr[5] : "stop";

    // Status-Flag, um Events während der Benutzerinteraktion zu blockieren
    let isUserInteracting = false;
    let interactionTimeout = null;

    // --- CSS ---
    if (!$('#shutter-h-widget-style').length) {
        $('<style id="shutter-h-widget-style">')
        .prop('type', 'text/css')
        .html(`
            .shutter-h-card {
                background: var(--bg-color, rgba(120,120,120,0.15)) !important;
                border: 1px solid var(--border-color, rgba(120,120,120,0.3)) !important;
                border-radius: 10px !important;
                padding: 5px !important;
                box-shadow: 0 3px 8px rgba(0,0,0,0.2) !important;
                color: var(--text-color, inherit) !important;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
                min-width: 180px !important;
                max-width: 260px !important;
                display: inline-block !important;
                box-sizing: border-box !important;
            }
            .shutter-h-btn-group {
                display: flex !important;
                justify-content: space-between !important;
                gap: 8px !important;
                margin-bottom: 10px !important;
            }
            .shutter-h-btn {
                flex: 1 !important;
                background: rgba(120, 120, 120, 0.2) !important;
                border: none !important;
                border-radius: 6px !important;
                color: var(--text-color, #fff) !important;
                height: 36px !important;
                cursor: pointer !important;
                display: flex !important;
                justify-content: center !important;
                align-items: center !important;
                text-align: center !important;
                padding: 0 !important; 
                margin: 0 !important;
                transition: background 0.1s, transform 0.1s !important;
            }
            .shutter-h-btn:hover { background: rgba(120, 120, 120, 0.35) !important; }
            .shutter-h-btn:active { transform: scale(0.94) !important; background: rgba(47, 128, 237, 0.7) !important; }
            .shutter-h-btn svg { width: 24px !important; height: 24px !important; fill: currentColor !important; display: block !important; margin: 0 auto !important; padding: 0 !important; float: none !important; position: static !important; }
            .shutter-h-control-row {
                display: flex !important;
                align-items: center !important;
                gap: 10px !important;
                background: rgba(120, 120, 120, 0.1) !important;
                padding: 6px !important;
                border-radius: 6px !important;
            }
            .shutter-h-preview-window {
                width: 24px !important;
                height: 30px !important;
                background: rgba(255, 255, 255, 0.3) !important; 
                border: 1px solid rgba(120, 120, 120, 0.5) !important;
                border-radius: 3px !important;
                position: relative !important;
                overflow: hidden !important;
                flex-shrink: 0 !important;
            }
            .shutter-h-preview-lamellas {
                position: absolute !important;
                top: 0 !important;
                left: 0 !important;
                width: 100% !important;
                height: 100%; 
                background: var(--text-color, #444) !important; 
                opacity: 0.85 !important;
                transition: height 0.3s ease-in-out !important; 
                background-image: linear-gradient(rgba(0,0,0,0.3) 1px, transparent 1px) !important;
                background-size: 100% 4px !important;
            }
            .shutter-h-slider {
                flex: 1 !important;
                -webkit-appearance: none !important;
                appearance: none !important;
                height: 6px !important;
                border-radius: 3px !important;
                background: rgba(120, 120, 120, 0.3) !important;
                outline: none !important;
                border: none !important;
                margin: 0 !important;
                padding: 0 !important;
            }
            .shutter-h-slider::-webkit-slider-thumb { -webkit-appearance: none !important; appearance: none !important; width: 22px !important; height: 22px !important; border-radius: 50% !important; background: #2f80ed !important; cursor: pointer !important; box-shadow: 0 1px 4px rgba(0,0,0,0.3) !important; }
            .shutter-h-slider::-moz-range-thumb { width: 22px !important; height: 22px !important; border: none !important; border-radius: 50% !important; background: #2f80ed !important; cursor: pointer !important; box-shadow: 0 1px 4px rgba(0,0,0,0.3) !important; }
            .shutter-h-val { font-size: 13px !important; font-weight: 700 !important; min-width: 34px !important; text-align: right !important; }
        `)
        .appendTo('head');
    }

    // --- HTML Struktur ---
    const wrapper = $('<div/>', {
        id: dev + "_shutter_h_wrapper",
        class: 'shutter-h-card',
        informid: dev + '-shutter-h-state'
    });

    wrapper.on('click', function(e) { e.stopPropagation(); });

    const btnGroup = $('<div/>', { class: 'shutter-h-btn-group' }).appendTo(wrapper);

    const iconUp   = '<svg viewBox="0 0 24 24"><path d="M7.41,15.41L12,10.83L16.59,15.41L18,14L12,8L6,14L7.41,15.41Z"/></svg>';
    const iconStop = '<svg viewBox="0 0 24 24"><path d="M18,18H6V6H18V18Z"/></svg>';
    const iconDown = '<svg viewBox="0 0 24 24"><path d="M7.41,8.58L12,13.17L16.59,8.58L18,10L12,16L6,10L7.41,8.58Z"/></svg>';

    const btnUp   = $('<button/>', { class: 'shutter-h-btn', html: iconUp, title: 'Öffnen' }).appendTo(btnGroup);
    const btnStop = $('<button/>', { class: 'shutter-h-btn', html: iconStop, title: 'Stop' }).appendTo(btnGroup);
    const btnDown = $('<button/>', { class: 'shutter-h-btn', html: iconDown, title: 'Schließen' }).appendTo(btnGroup);

    const controlRow = $('<div/>', { class: 'shutter-h-control-row' }).appendTo(wrapper);
    const animWindow = $('<div/>', { class: 'shutter-h-preview-window' }).appendTo(controlRow);
    const animLamellas = $('<div/>', { class: 'shutter-h-preview-lamellas' }).appendTo(animWindow);

    const initialVal = parseInt(currVal) || 0;

    const slider = $('<input/>', {
        type: 'range',
        class: 'shutter-h-slider',
        min: '0',
        max: '100',
        value: initialVal
    }).appendTo(controlRow);

    const sliderValDisplay = $('<span/>', { class: 'shutter-h-val', text: `${initialVal}%` }).appendTo(controlRow);

    // --- Inverser Modus: 0% = Zu (100% Höhe), 100% = Offen (0% Höhe) ---
    function updateVisualShutter(percent) {
        const p = Math.min(Math.max(parseInt(percent) || 0, 0), 100);
        const invertedHeight = 100 - p;
        animLamellas.css('height', invertedHeight + '%');
    }

    function applyNewValue(val) {
        const numericVal = Math.min(Math.max(parseInt(val) || 0, 0), 100);
        slider.val(numericVal);
        sliderValDisplay.text(`${numericVal}%`);
        updateVisualShutter(numericVal);
    }

    // --- FHEM API ---
    function sendCmdToFhem(action, value) {
        let fullCmd = "";
        if (action === 'position') {
            fullCmd = `{fhem("set ${dev} ${targetSetCmd} ${value}")}`;
        } else if (action === 'open') {
            fullCmd = `{fhem("set ${dev} ${readingUp}")}`;
        } else if (action === 'close') {
            fullCmd = `{fhem("set ${dev} ${readingDown}")}`;
        } else if (action === 'stop') {
            fullCmd = `{fhem("set ${dev} ${readingStop}")}`;
        } else {
            fullCmd = `{fhem("set ${dev} ${action}")}`;
        }
        FW_cmd(FW_root + '?cmd=' + encodeURIComponent(fullCmd) + '&XHR=1');
    }

    // --- Event-Handler für Buttons ---
    btnUp.on('click', function(e) { e.preventDefault(); e.stopPropagation(); sendCmdToFhem('open'); });
    btnStop.on('click', function(e) { e.preventDefault(); e.stopPropagation(); sendCmdToFhem('stop'); });
    btnDown.on('click', function(e) { e.preventDefault(); e.stopPropagation(); sendCmdToFhem('close'); });

    slider.on('input', function(e) {
        isUserInteracting = true;
        if (interactionTimeout) clearTimeout(interactionTimeout);
        sliderValDisplay.text(`${this.value}%`);
        updateVisualShutter(this.value); 
    });

    slider.on('change', function(e) {
        e.preventDefault(); e.stopPropagation();
        sendCmdToFhem('position', this.value);
        
        if (interactionTimeout) clearTimeout(interactionTimeout);
        interactionTimeout = setTimeout(function() {
            isUserInteracting = false;
        }, 1500);
    });

    // --- Live-Updates gebunden an current_position ---
    const informId = `${dev}-${readingPosition}`;

    let hiddenUpdateDiv = document.getElementById(informId);
    if (!hiddenUpdateDiv) {
        hiddenUpdateDiv = document.createElement('div');
        hiddenUpdateDiv.id = informId;
        hiddenUpdateDiv.style.display = 'none';
        hiddenUpdateDiv.setAttribute('informId', informId);
        
        hiddenUpdateDiv.setValueFn = function(newValue) {
            if (!isUserInteracting) {
                applyNewValue(newValue);
            }
        };
        wrapper.append(hiddenUpdateDiv);
    }

    // Initiales Einlesen beim Laden
    FW_queryValue(`{ReadingsVal("${dev}","${readingPosition}","0")}`, {
        setValueFn: function(val) {
            if (!isUserInteracting) {
                applyNewValue(val);
            }
        }
    });

    // Sofort-Sichtbarkeit beim Rendern
    updateVisualShutter(initialVal);

    return wrapper[0];
}