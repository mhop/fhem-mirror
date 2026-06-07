FW_version["fhemweb_shutter_v.js"] = "$Id: fhemweb_shutter_v.js 0.8.4 schwatter $";
FW_widgets['shutter_v'] = { createFn: window.controlShutterVCreate };

function controlShutterVCreate(elName, devName, vArr, currVal, set, params, cmd) {
    const dev = devName || 'unknown';

    if ($(`div.shutter_widget_container[informid="${dev}-shutter-v-state"]`).length) {
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
    if (!$('#shutter-v-widget-style').length) {
        $('<style id="shutter-v-widget-style">')
        .prop('type', 'text/css')
        .html(`
            .shutter-v-card {
                background: var(--bg-color, rgba(120,120,120,0.15)) !important;
                border: 1px solid var(--border-color, rgba(120,120,120,0.3)) !important;
                border-radius: 10px !important;
                padding: 8px !important; 
                box-shadow: 0 3px 8px rgba(0,0,0,0.2) !important;
                color: var(--text-color, inherit) !important;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
                min-width: 160px !important;
                max-width: 180px !important;
                display: flex !important;
                gap: 10px !important;
                align-items: center !important;
                box-sizing: border-box !important;
                position: relative !important;
            }
            .shutter-v-btn-column {
                display: flex !important;
                flex-direction: column !important;
                gap: 5px !important;
                flex: 1 !important;
            }
            .shutter-v-btn {
                background: rgba(120, 120, 120, 0.2) !important;
                border: none !important;
                border-radius: 6px !important;
                color: var(--text-color, #fff) !important;
                height: 30px !important;
                cursor: pointer !important;
                display: flex !important;
                justify-content: center !important;
                align-items: center !important;
                text-align: center !important;
                padding: 0 !important; 
                margin: 0 !important;
                transition: background 0.1s, transform 0.1s !important;
                width: 100% !important;
            }
            .shutter-v-btn:hover { background: rgba(120, 120, 120, 0.35) !important; }
            .shutter-v-btn:active { transform: scale(0.94) !important; background: rgba(47, 128, 237, 0.7) !important; }
            .shutter-v-btn svg { 
                width: 20px !important; 
                height: 20px !important; 
                fill: currentColor !important; 
                display: block !important; 
                margin: 0 auto !important;
                padding: 0 !important;
                float: none !important;
                position: static !important;
            }
            
            .shutter-v-touch-window {
                width: 60px !important;
                height: 100px !important;
                border: 2px solid rgba(120, 120, 120, 0.5) !important;
                border-radius: 5px !important;
                position: relative !important;
                flex-shrink: 0 !important;
                cursor: ns-resize !important;
                user-select: none !important;
                -webkit-user-select: none !important;
                transition: background-color 0.2s ease-out !important;
                overflow: hidden !important; /* Wieder sicher aktiviert für die Lamellen */
            }
            .shutter-v-preview-lamelines { /* umbenannt zur Sicherheit vor Altresten */
                position: absolute !important;
                top: 0 !important;
                left: 0 !important;
                width: 100% !important;
                height: 100%; 
                background: var(--text-color, #444) !important; 
                opacity: 0.9 !important;
                pointer-events: none !important;
                transition: height 0.2s ease-out !important; 
                background-image: linear-gradient(rgba(0,0,0,0.3) 1px, transparent 1px) !important;
                background-size: 100% 6px !important;
            }
            .shutter-v-val-overlay {
                position: absolute !important;
                bottom: 2px !important;
                left: 0 !important;
                width: 100% !important;
                text-align: center !important;
                font-size: 11px !important;
                font-weight: bold !important;
                text-shadow: 1px 1px 2px rgba(120,120,120,0.4) !important;
                pointer-events: none !important;
                z-index: 10 !important;
                transition: color 0.1s ease-out !important;
            }
            /* Die absolut immunisierte Bubble im Body-Bereich */
            .shutter-v-popup-indicator {
                position: absolute !important;
                background: #2f80ed !important;
                color: #fff !important;
                padding: 4px 8px !important;
                border-radius: 5px !important;
                font-size: 14px !important;
                font-weight: bold !important;
                box-shadow: 0 4px 10px rgba(0,0,0,0.3) !important;
                pointer-events: none !important;
                z-index: 99999 !important;
                display: none;
                white-space: nowrap !important;
                transform: translateX(-50%) !important;
            }
            .shutter-v-popup-indicator::after {
                content: '' !important;
                position: absolute !important;
                left: 50% !important;
                transform: translateX(-50%) !important;
                border-style: solid !important;
                display: block !important;
                width: 0 !important;
            }
            /* Pfeil zeigt nach unten (wenn oben platziert) */
            .shutter-v-popup-arrow-down::after {
                bottom: -5px !important;
                top: auto !important;
                border-width: 5px 5px 0 !important;
                border-color: #2f80ed transparent !important;
            }
            /* Pfeil zeigt nach oben (wenn unten platziert) */
            .shutter-v-popup-arrow-up::after {
                top: -5px !important;
                bottom: auto !important;
                border-width: 0 5px 5px !important;
                border-color: transparent transparent #2f80ed !important;
            }
        `)
        .appendTo('head');
    }

    // --- HTML Struktur ---
    const wrapper = $('<div/>', {
        id: dev + "_shutter_v_wrapper",
        class: 'shutter-v-card',
        informid: dev + '-shutter-v-state'
    });

    wrapper.on('click', function(e) { e.stopPropagation(); });

    const animWindow = $('<div/>', { class: 'shutter-v-touch-window' }).appendTo(wrapper);
    const animLamellas = $('<div/>', { class: 'shutter-v-preview-lamelines' }).appendTo(animWindow);
    const valDisplay = $('<div/>', { class: 'shutter-v-val-overlay', text: '0%' }).appendTo(animWindow);
    const popupIndicator = $('<div/>', { class: 'shutter-v-popup-indicator', text: '0%' }).appendTo('body');
    const btnColumn = $('<div/>', { class: 'shutter-v-btn-column' }).appendTo(wrapper);

    const iconUp   = '<svg viewBox="0 0 24 24"><path d="M7.41,15.41L12,10.83L16.59,15.41L18,14L12,8L6,14L7.41,15.41Z"/></svg>';
    const iconStop = '<svg viewBox="0 0 24 24"><path d="M18,18H6V6H18V18Z"/></svg>';
    const iconDown = '<svg viewBox="0 0 24 24"><path d="M7.41,8.58L12,13.17L16.59,8.58L18,10L12,16L6,10L7.41,8.58Z"/></svg>';

    const btnUp   = $('<button/>', { class: 'shutter-v-btn', html: iconUp, title: 'Öffnen' }).appendTo(btnColumn);
    const btnStop = $('<button/>', { class: 'shutter-v-btn', html: iconStop, title: 'Stop' }).appendTo(btnColumn);
    const btnDown = $('<button/>', { class: 'shutter-v-btn', html: iconDown, title: 'Schließen' }).appendTo(btnColumn);

    let currentInternalPercent = parseInt(currVal) || 0;

    function updateVisualShutter(percent) {
        const p = Math.min(Math.max(parseInt(percent) || 0, 0), 100);
        currentInternalPercent = p;
        const invertedHeight = 100 - p;
        animLamellas.css('height', invertedHeight + '%');
        valDisplay.text(`${p}%`);
        popupIndicator.text(`${p}%`);

        const brightness = Math.round(30 + (p * 2.25)); 
        animWindow.css('background-color', `rgb(${brightness}, ${brightness}, ${brightness})`);

        if (p < 50) {
            valDisplay.css('color', 'rgb(255, 255, 255)');
        } else {
            valDisplay.css('color', 'rgb(0, 0, 0)');
        }
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

    // --- Dynamische, skin-sichere Positionierungs-Logik ---
    function handleSizingFromEvent(e) {
        const rect = animWindow[0].getBoundingClientRect();
        const isTouch = !!(e.originalEvent && e.originalEvent.touches && e.originalEvent.touches.length) || !!(e.touches && e.touches.length);
        const clientY = e.clientY || (isTouch ? (e.originalEvent?.touches?.[0]?.clientY ?? e.touches[0].clientY) : rect.top);
        
        let relativeY = clientY - rect.top;
        if (relativeY < 0) relativeY = 0;
        if (relativeY > rect.height) relativeY = rect.height;

        let percent = Math.round(100 - (relativeY / rect.height * 100));
        
        isUserInteracting = true;
        if (interactionTimeout) clearTimeout(interactionTimeout);

        updateVisualShutter(percent);

        if (isTouch) {
            // Absolute Koordinaten auf der Gesamten Seite ermitteln
            const windowCenterX = rect.left + window.scrollX + (rect.width / 2);
            const windowTopY = rect.top + window.scrollY;
            
            let finalTop = windowTopY - 45; // Standard: Oben (-45px)
            let useBottomLayout = (percent > 50); // Ab 51% nach unten wandern
            
            // Browsergrenzen prüfen (Platz nach oben/unten im aktuellen Viewport)
            const spaceAbove = rect.top;
            const spaceBelow = window.innerHeight - rect.bottom;
            
            if (!useBottomLayout && spaceAbove < 50) {
                // Eigentlich oben geplant, aber am oberen Rand -> nach unten zwingen
                useBottomLayout = true;
            } else if (useBottomLayout && spaceBelow < 50) {
                // Eigentlich unten geplant, aber am unteren Rand -> nach oben zwingen
                useBottomLayout = false;
            }

            // Finale Zuweisung basierend auf der Entscheidung
            if (useBottomLayout) {
                finalTop = rect.bottom + window.scrollY + 15; // Unten platzieren (+15px Puffer)
                popupIndicator.addClass('shutter-v-popup-arrow-up').removeClass('shutter-v-popup-arrow-down');
            } else {
                popupIndicator.addClass('shutter-v-popup-arrow-down').removeClass('shutter-v-popup-arrow-up');
            }

            popupIndicator.css({
                display: 'block',
                top: finalTop + 'px',
                left: windowCenterX + 'px'
            });
        } else {
            popupIndicator.hide();
        }
    }

    animWindow.on('mousedown touchstart', function(e) {
        e.preventDefault(); e.stopPropagation();
        handleSizingFromEvent(e);

        const moveNamespace = `mousemove.shuttervdrag-${dev} touchmove.shuttervdrag-${dev}`;
        const upNamespace = `mouseup.shuttervdrag-${dev} touchend.shuttervdrag-${dev}`;

        $(window).on(moveNamespace, function(ev) {
            handleSizingFromEvent(ev);
        });

        $(window).on(upNamespace, function(ev) {
            $(window).off(`.shuttervdrag-${dev}`);
            popupIndicator.hide();
            
            sendCmdToFhem('position', currentInternalPercent);

            if (interactionTimeout) clearTimeout(interactionTimeout);
            interactionTimeout = setTimeout(function() {
                isUserInteracting = false;
            }, 1500);
        });
    });

    // --- Live-Updates gebunden an die Position ---
    const informId = `${dev}-${readingPosition}`;

    let hiddenUpdateDiv = document.getElementById(informId);
    if (!hiddenUpdateDiv) {
        hiddenUpdateDiv = document.createElement('div');
        hiddenUpdateDiv.id = informId;
        hiddenUpdateDiv.style.display = 'none';
        hiddenUpdateDiv.setAttribute('informId', informId);
        hiddenUpdateDiv.setValueFn = function(newValue) {
            if (!isUserInteracting) {
                updateVisualShutter(newValue);
            }
        };
        wrapper.append(hiddenUpdateDiv);
    }

    // Initiales Einlesen beim Laden
    FW_queryValue(`{ReadingsVal("${dev}","${readingPosition}","0")}`, {
        setValueFn: function(val) {
            if (!isUserInteracting) {
                updateVisualShutter(val);
            }
        }
    });

    // Sofort-Sichtbarkeit beim Rendern
    updateVisualShutter(currentInternalPercent);

    return wrapper[0];
}