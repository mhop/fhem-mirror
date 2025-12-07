FW_version["fhemweb_minichart.js"] = "$Id: fhemweb_minichart.js 0.6.3 schwatter $";
FW_widgets['minichart'] = { createFn: miniChartCreate };

function miniChartCreate(elName, devName, vArr, currVal, set, params, cmd) {
    console.log("[minichart] createFn called", { elName, devName, vArr });

    const $el  = typeof elName === 'string' ? $('#' + elName) : $(elName);
    const dev  = devName || ($el.attr('id') || 'unknown');

    $(`td[informid="${dev}"]`).remove();
    $el.empty();

    if (!Array.isArray(vArr) || vArr.length < 5) {
        $el.text("?? Invalid widget parameters – need 4 readings");
        return;
    }

    //------------------------------------------------------
    // PARSE vArr DYNAMISCH (LABEL@READING@UNIT)
    //------------------------------------------------------
    function parseTriple(s) {
        const p = (s || "").split("@");
        return {
            label:   (p[0] && p[0] !== "") ? p[0] : "\u00A0",
            reading: (p[1] && p[1] !== "") ? p[1] : "\u00A0",
            unit:    (p[2] && p[2] !== "") ? p[2] : ""
        };
    }

    const row1 = parseTriple(vArr[1]);
    const row2 = parseTriple(vArr[2]);
    const row3 = parseTriple(vArr[3]);
    const chartParam = vArr[4];
    const chartParts = (vArr[5] || "").split("@");
    let chartType = chartParts[0] || "line";
    let color1 = chartParts[1] || "#3b82f6";
    let color2 = chartParts[2] || "#3b82f6";

    let currentValue01 = "-";
    let currentValue02 = "-";
    let currentValue03 = "-";
    let chartValues = [];

    //------------------------------------------------------
    // WIDGET UI (HTML)
    //------------------------------------------------------
    const wrapper = $('<div/>', { id: dev + "_wrapper", style: `display:block !important; width:100%; position:relative; font-family:sans-serif;` });
    const html = `
    <style>
        #${dev}-mobile { display:block; }
        #${dev}-desktop { display:none; }
        @media screen and (min-width: 900px) {
            #${dev}-mobile { display:none !important; }
            #${dev}-desktop { display:block !important; }
        }
    </style>

    <!-- MOBILE -->
    <div id="${dev}-mobile" style="width:365px; padding:10px; border:1px solid transparent; border-radius:6px; box-shadow:none; height:90px; position:relative; box-sizing:border-box;">
        <div style="position:absolute; top:10px; left:0px; width:90px; font-size:14px; line-height:26px; text-align:left;">
            <div style="display:block;">${row1.label}</div>
            <div style="display:block;">${row2.label}</div>
            <div style="display:block;">${row3.label}</div>
        </div>
        <div id="${dev}_val_mobile" style="position:absolute; top:10px; left:80px; width:120px; font-size:14px; font-weight:bold; text-align:left; line-height:26px; display:flex; flex-direction:column;">
            <div>-</div><div>-</div><div>-</div>
        </div>
        <div id="${dev}_chart_mobile" style="position:absolute; top:10px; right:10px; width:160px; height:70px; overflow:hidden;"></div>
    </div>

    <!-- DESKTOP -->
    <div id="${dev}-desktop" style="width:1050px; padding:10px; border:1px solid transparent; border-radius:6px; box-shadow:none; height:90px; position:relative; box-sizing:border-box;">
        <div style="position:absolute; top:10px; left:00px; width:100px; font-size:14px; line-height:26px; text-align:left;">
            <div style="display:block;">${row1.label}</div>
            <div style="display:block;">${row2.label}</div>
            <div style="display:block;">${row3.label}</div>
        </div>
        <div id="${dev}_val_desktop" style="position:absolute; top:10px; left:80px; width:130px; font-size:14px; font-weight:bold; text-align:left; line-height:26px; display:flex; flex-direction:column;">
            <div>-</div><div>-</div><div>-</div>
        </div>
        <div id="${dev}_chart_desktop" style="position:absolute; top:10px; right:10px; width:780px; height:70px; overflow:hidden;"></div>
    </div>
    `;
    wrapper.html(html);
    $el.append(wrapper);

    //------------------------------------------------------
    // HIDDEN DIVS
    //------------------------------------------------------
    function createHidden(id, fn) {
        if (!id) return;
        const d = document.createElement('div');
        d.style.display = "none";
        d.setAttribute("informid", `${dev}-${id}`);
        d.setValueFn = fn;
        wrapper[0].appendChild(d);
        FW_queryValue(`{ReadingsVal("${dev}","${id}","")}`, { setValueFn: val => d.setValueFn(val) });
    }

    createHidden(row1.reading, v => { currentValue01 = v; updateTextOutput(); });
    createHidden(row2.reading, v => { currentValue02 = v; updateTextOutput(); });
    createHidden(row3.reading, v => { currentValue03 = v; updateTextOutput(); });

    createHidden(chartParam, v => {
        if(!v) return;
        chartValues = v.split(',').map(Number).filter(n => !isNaN(n));
        if(chartType==="line") renderLineChart(chartValues);
        else renderBarChart(chartValues);
    });

    //------------------------------------------------------
    // UPDATE TEXT OUTPUT
    //------------------------------------------------------
    function updateTextOutput() {
        function out(val, unit) { if(val===undefined||val===null||val==="") return "\u00A0"; return unit?`${val} ${unit}`:val; }
        const mob = document.getElementById(`${dev}_val_mobile`);
        const des = document.getElementById(`${dev}_val_desktop`);
        if(!mob||!des) return;
        mob.children[0].textContent = out(currentValue01,row1.unit);
        mob.children[1].textContent = out(currentValue02,row2.unit);
        mob.children[2].textContent = out(currentValue03,row3.unit);
        des.children[0].textContent = out(currentValue01,row1.unit);
        des.children[1].textContent = out(currentValue02,row2.unit);
        des.children[2].textContent = out(currentValue03,row3.unit);
    }

    //------------------------------------------------------
    // LINE CHART FUNCTION
    //------------------------------------------------------
    function renderLineChart(arr){
        renderLine(arr,"mobile",40,3,160);
        const desktopDiv = document.getElementById(`${dev}_chart_desktop`);
        let desktopWidth = 780;
        if(desktopDiv){
            const w = desktopDiv.clientWidth || desktopDiv.offsetWidth;
            if(w>50) desktopWidth=w;
        }
        renderLine(arr,"desktop",220,3,desktopWidth);
    }

    function renderLine(arr, mode, count, win, width){
        const div = document.getElementById(`${dev}_chart_${mode}`);
        if(!div) return;
        div.innerHTML = "";

        let v = arr.slice(-count);
        let out = [];
        for(let i=0;i<v.length;i++){
            let start = Math.max(0,i-win+1);
            let slice=v.slice(start,i+1);
            out.push(slice.reduce((a,b)=>a+b,0)/slice.length);
        }
        v=out;
        if(v.length<2) return;

        let vmin=Math.min(...v);
        let vmax=Math.max(...v);
        let min = vmin<0?vmin:0;
        let max = vmax>0?vmax:0;
        let range = (max-min)||1;

        const hTotal=70,padTop=2,padBot=2,height=hTotal-padTop-padBot;
        const zeroY=padTop+(height-((0-min)/range*height));
        const step=width/(v.length-1);
        const pts=v.map((val,i)=>[i*step,padTop+(height-((val-min)/range*height))]);

        const pathD=pts.map((p,i)=>i===0?`M${p[0]},${p[1]}`:`L${p[0]},${p[1]}`).join(' ');
        const areaD=pathD+` L${width},${zeroY} L0,${zeroY} Z`;

        const svg=document.createElementNS("http://www.w3.org/2000/svg","svg");
        svg.setAttribute("width",width); svg.setAttribute("height",hTotal);
        svg.setAttribute("viewBox",`0 0 ${width} ${hTotal}`);
        svg.setAttribute("preserveAspectRatio","xMidYMid meet");
        svg.style.cssText=`width:${width}px!important;height:${hTotal}px!important;max-width:${width}px!important;max-height:${hTotal}px!important;overflow:hidden;display:block;padding:0;margin:0;`;

        const defs=document.createElementNS(svg.namespaceURI,"defs");
        const grad=document.createElementNS(svg.namespaceURI,"linearGradient");
        grad.setAttribute("id",`${dev}_${mode}_grad`);
        grad.setAttribute("x1","0");grad.setAttribute("y1","0");
        grad.setAttribute("x2","0");grad.setAttribute("y2","1");

        function stop(offset,color,op){
            const s=document.createElementNS(svg.namespaceURI,"stop");
            s.setAttribute("offset",offset);
            s.setAttribute("stop-color",color);
            s.setAttribute("stop-opacity",op);
            grad.appendChild(s);
        }

        if(vmin<0&&vmax>0){stop("0%",color1,0.2);stop("50%",color1,0.0);stop("100%",color2,0.2);}
        else if(vmin>=0){stop("0%",color1,0.8);stop("100%",color1,0.0);}
        else{stop("0%",color2,0.0);stop("100%",color2,0.8);}

        defs.appendChild(grad); svg.appendChild(defs);

        const area=document.createElementNS(svg.namespaceURI,"path");
        area.setAttribute("d",areaD);
        area.setAttribute("fill",`url(#${dev}_${mode}_grad)`);
        svg.appendChild(area);

        const zero=document.createElementNS(svg.namespaceURI,"line");
        zero.setAttribute("x1","0"); zero.setAttribute("x2",width);
        zero.setAttribute("y1",zeroY); zero.setAttribute("y2",zeroY);
        zero.setAttribute("stroke","white"); zero.setAttribute("stroke-width","1"); zero.setAttribute("stroke-dasharray","2,2");
        svg.appendChild(zero);

        const line=document.createElementNS(svg.namespaceURI,"path");
        line.setAttribute("d",pathD); line.setAttribute("fill","none"); line.setAttribute("stroke",color1); line.setAttribute("stroke-width","2");
        svg.appendChild(line);

        div.appendChild(svg);
    }

    //------------------------------------------------------
    // BAR CHART FUNCTION
    //------------------------------------------------------
    function renderBarChart(arr){
        ["mobile","desktop"].forEach((mode)=>{
            const width = mode==="mobile"?160:780;
            const height=70;
            const div=document.getElementById(`${dev}_chart_${mode}`);
            if(!div) return;
            div.innerHTML="";

            const v=arr.slice(- (mode==="mobile"?40:220)); // nur so viele Werte wie linechart
            const min=Math.min(...v,0); const max=Math.max(...v,0); const range=max-min||1;
            const zeroY=height-((0-min)/range*height);
            const w=width/(v.length-1||1); const barWidth=w*0.6;

            const svg=document.createElementNS("http://www.w3.org/2000/svg","svg");
            svg.setAttribute("width",width); svg.setAttribute("height",height);
            svg.setAttribute("viewBox",`0 0 ${width} ${height}`);
            svg.setAttribute("preserveAspectRatio","none");
            svg.style.cssText=`position:absolute;top:0;left:0;width:${width}px;height:${height}px`;

            v.forEach((val,i)=>{
                const x=i*w-barWidth/2;
                const y=height-((val-min)/range*height);
                let barY,barH;
                const color = val>=0 ? color1 : color2;
                if(val>=0){barY=y;barH=zeroY-y;}else{barY=zeroY;barH=y-zeroY;}

                const rect=document.createElementNS(svg.namespaceURI,"rect");
                rect.setAttribute("x",x); rect.setAttribute("y",barY);
                rect.setAttribute("width",barWidth); rect.setAttribute("height",barH);
                rect.setAttribute("fill",color); rect.setAttribute("opacity","0.8");
                svg.appendChild(rect);
            });

            div.appendChild(svg);
        });
    }

    console.log("[minichart] initialized for", dev);
    return wrapper[0];
}

/*
=pod
=begin html
  <li>minichart,&lt;label1@reading1@unit1&gt;,&lt;label2@reading2@unit2&gt;,&lt;label3@reading3@unit3&gt;,
      &lt;chart-reading&gt;,&lt;chart-type@color-pos@color-neg&gt;
      - compact widget with three values and a small trend chart.<br>
      See <a href='https://wiki.fhem.de/wiki/FHEMWEB/MiniChart'>FHEMWEB/MiniChart</a> for documentation and examples.</li><br>
=end html
=begin html_DE
  <li>minichart,&lt;label1@reading1@unit1&gt;,&lt;label2@reading2@unit2&gt;,&lt;label3@reading3@unit3&gt;,
      &lt;chart-reading&gt;,&lt;chart-type@color-pos@color-neg&gt;
      - kompaktes Widget mit drei Werten und kleinem Trenddiagramm.<br>
      Siehe <a href='https://wiki.fhem.de/wiki/FHEMWEB/MiniChart'>FHEMWEB/MiniChart</a> für Dokumentation und Beispiele.</li><br>
=end html_DE
=cut
*/
