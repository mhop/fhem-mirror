FW_version["fhemweb_popup.js"] = "$Id: fhemweb_popup.js 2.5.2 $";
FW_widgets['popup'] = { createFn: popupWidgetCreate };

function popupWidgetCreate(elName, devName, vArr, currVal, set, params, cmd) {
    // FW_callCreateFn ruft JEDE geladene createFn für JEDES Widget auf:
    // alles, was nicht "popup" ist, muss hier zurück an FHEM.
    if (!vArr || vArr[0] !== 'popup') return undefined;

    const dev = devName || 'unknown';
    const readingsConfig = vArr.slice(1);

    // CSS für das Popup und das REINE CSS-MENÜ-ICON
    const styleId = 'fhemwebPopupWidgetStyles';
    if (!document.getElementById(styleId)) {
        const style = document.createElement('style');
        style.id = styleId;
        // Nur Layout: Farben, Schrift und Rahmen kommen aus dem FHEM-Style
        style.textContent = `
            .fhem-popup-container { outline: none; }
            .fhem-popup-table td { vertical-align: middle; padding-top: 8px; padding-bottom: 8px; }
            .fhem-popup-table td:first-child > div { text-align: left; }
            .fhem-popup-table td:last-child > div { text-align: right; }
            .fhem-popup-icon { display: inline-block; width: 24px; height: 24px; margin-right: 8px; vertical-align: middle; }
            .fhem-popup-icon svg { width: 100%; height: 100%; fill: currentColor; }

            /* f18 blendet im Hochformat (<=480px) alle Spalten ab der 3. aus
               (#content.slim ... td:nth-child(n+3)). Die Popup-Spalte bleibt sichtbar. */
            @media screen and (max-width: 480px) and (orientation: portrait) {
                #content.slim table.block tr td.fhem-popup-td { display: table-cell !important; width: auto !important; }
                #content.slim table.block.wrapcolumns tr td.fhem-popup-td { display: block !important; }
            }

            .fhem-popup-btn { display: inline-block; padding: 6px; cursor: pointer; vertical-align: middle; }
            .css-hamburger { display: flex; flex-direction: column; justify-content: space-between; width: 16px; height: 12px; }
            .css-hamburger span { display: block; height: 2px; background-color: currentColor; }
        `;
        document.head.appendChild(style);
    }

    // Mit Icon steht das Icon links, ohne Icon bleibt der Reading-Name
    const showIcon = ($row) => {
        $row.find('.fhem-popup-icon').show();
        $row.find('.fhem-popup-label').hide();
    };

    // Beschriftung einer webCmd-Zelle. Icons (cmdIcon) enthalten im SVG auch
    // Metadaten-Text, darum nie den Text der Zelle samt Icon verwenden.
    const widgetLabel = ($td) => {
        const informId = $td.find('[informId]').addBack('[informId]').attr('informId');
        if (informId) return informId.replace(`${dev}-`, '');
        const $icon = $td.find('[data-txt], img[title]').first();
        if ($icon.length) return $icon.attr('data-txt') || $icon.attr('title');
        const $copy = $td.clone();
        $copy.find('svg').remove();
        return $copy.text().trim();
    };

    // Popup-Logik über native FW_okDialog
    const openPopupDialog = () => {
        $('#fhem_popup_content').remove();
        
        // autofocus: jQuery UI fokussiert sonst das erste Bedienelement, und ein
        // Colorpicker klappt dabei sofort auf
        const $popupContent = $('<div id="fhem_popup_content" class="fhem-popup-container" tabindex="-1" autofocus></div>');
        $popupContent.append($('<span class="mkTitle"></span>').text(`Details: ${dev}`));

        // Dieselbe Tabelle wie FHEMs Detailseite, f18 erbt auch wrapcolumns
        const $table = $('<table class="block wide fhem-popup-table"></table>')
            .toggleClass('wrapcolumns', $('table.block').first().hasClass('wrapcolumns'));
        $popupContent.append($table);
        let rowCount = 0;
        const rowClass = () => (rowCount++ % 2 ? 'even' : 'odd');

        readingsConfig.forEach((cfg, index) => {
            const parts = cfg.split('@');
            const readingName = parts[0];
            const unit = parts[1] || '';
            
            // Der Attributname lautet z.B. icon_1 für das erste Element
            const attrName = `icon_${index + 1}`;
            const rowId = `popup_row_${dev}_${readingName}`.replace(/[^a-zA-Z0-9_-]/g,'_');
            
            const $row = $(`
                <tr class="${rowClass()}" id="${rowId}">
                    <td><div class="col1">
                        <span class="fhem-popup-icon" title="${readingName}" style="display:none"></span>
                        <span class="fhem-popup-label">${readingName}</span>
                    </div></td>
                    <td><div class="dval">
                        <span class="fhem-popup-value">...</span> ${unit}
                    </div></td>
                </tr>
            `);
            $table.append($row);

            // Abfrage des individuellen userattr für das Icon (z.B. icon_1)
            FW_queryValue(`{AttrVal("${dev}","${attrName}","")}`, {
                setValueFn: function(iconVal) {
                    if (iconVal) {
                        const $iconSpan = $row.find('.fhem-popup-icon');
                        if (iconVal.startsWith('data:image/svg+xml')) {
                            // Wenn es eine SVG-DataURL ist, dekodieren und direkt als SVG einsetzen
                            try {
                                const svgText = decodeURIComponent(iconVal.split(',')[1]);
                                $iconSpan.html(svgText);
                                showIcon($row);
                            } catch(e) {
                                console.error("Fehler beim Dekodieren des SVG-Icons: " + attrName, e);
                            }
                        } else {
                            // Andernfalls als normale Icon-Klasse (z.B. mdi- oder fa-) behandeln
                            let iconClass = iconVal;
                            if (iconClass.startsWith('mdi-')) { iconClass = `mdi ${iconClass}`; }
                            $iconSpan.html(`<i class="${iconClass}"></i>`);
                            showIcon($row);
                        }
                    }
                }
            });

            FW_queryValue(`{ReadingsVal("${dev}","${readingName}","")}`, {
                setValueFn: function(val) { $row.find('.fhem-popup-value').text(val); }
            });

            const popupInformer = $('<div/>', { informid: dev + '-' + readingName, style: 'display:none' });
            popupInformer[0].setValueFn = function(val) { $row.find('.fhem-popup-value').text(val); };
            $popupContent.append(popupInformer);
        });

        // Wie FW_smallScreenCommands: Die fertigen webCmd-Zellen wandern aus der
        // Gerätezeile in den Dialog und beim Schließen zurück. Der Platzhalter
        // hält die Reihenfolge der Spalten.
        const moved = [];
        $button.closest('tr').find('> td').has('.col3').not('.fhem-popup-td').each(function() {
            const $td = $(this);
            const $holder = $('<td style="display:none"></td>');
            const label = widgetLabel($td);
            $td.before($holder);
            moved.push({ $td, $holder });
            $(`<tr class="${rowClass()}"></tr>`)
                .append($('<td><div class="col1"></div></td>').find('div').text(label).end())
                .append($td.detach())
                .appendTo($table);
        });

        const reactivate = ($el) => $el.find('*').each(function() {
            if (this.activateFn) this.activateFn();
        });

        // Desktop: am Button, Touch-Gerät: ohne Bezugspunkt zentriert FW_okDialog
        const isTouch = window.matchMedia('(pointer: coarse)').matches;
        FW_okDialog($popupContent, isTouch ? undefined : $button);
        reactivate($table);   // Slider neu vermessen

        // Widgets, die ihre Zelle selbst ausblenden, hinterlassen keine leere Zeile.
        // Geprüft wird der Inline-Style: Die f18-Regel fürs Hochformat zählt nicht.
        $table.find('td').filter(function() {
            return this.style.display === 'none';
        }).closest('tr').hide();

        // dialogclose statt removeFn: FW_okDialog ruft removeFn bei Escape nicht auf
        $('#FW_okDialog').one('dialogclose', function() {
            moved.forEach(({ $td, $holder }) => {
                $holder.replaceWith($td);
                if ($td.is(':visible')) reactivate($td);
            });
            $('#fhem_popup_content').remove();
        });
    };

    // --- BUTTON MIT REINEN CSS-STRICHEN ERZEUGEN ---
    const $button = $(`
        <a class="fhem-popup-btn" title="Menü öffnen">
            <span class="css-hamburger">
                <span></span>
                <span></span>
                <span></span>
            </span>
        </a>
    `);
    
    $button.on('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        openPopupDialog();
    });

    // Ohne setValueFn überschreibt FHEM den Button-Inhalt bei jedem state-Event
    // mit dem Text des Readings (informId wird in FW_replaceWidget gesetzt).
    $button[0].setValueFn = function() {};

    // Das Einsetzen ins DOM übernimmt FW_replaceWidget (replaceWith); danach
    // ruft es activateFn auf, erst dann gibt es die umgebende Tabellenzelle.
    $button.activateFn = function() {
        $button.closest('td').addClass('fhem-popup-td');
    };

    return $button;
}