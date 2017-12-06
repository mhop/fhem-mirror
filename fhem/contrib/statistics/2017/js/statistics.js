
function loadGoogleApi(success) {
    
    if(window.google)
    {
        // Load the Visualization API library
        google.charts.load('current', {'packages':['corechart','geochart','table'], callback: success} ); 
    }
    else
    {
        success();
    }
}

function json2array(json){
    var result = [];
    var keys = Object.keys(json);
    keys.forEach(function(key){
        result.push([key,json[key]]);
    });
    return result;
}

function rand(length) {
    var text = "";
    var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    for(var i = 0; i < length; i++) {
        text += possible.charAt(Math.floor(Math.random() * possible.length));
    }
    return text;
}

function drawGooglePieChart(data, el, subst, sort, threshold) {
   
    sort = (sort == undefined ? "byKey" : sort);
    var id = rand(5);
   
    el.append("");
    el.append("<div id='"+id+"' class='googlepiechart'></div>");

    var result = [];

    for(var i in data) {
        result.push([((subst && i in subst) ? subst[i] : i)+" ("+data[i]+")", parseInt(data[i])]);
    }
   
    if(sort === "byKey") {
        result.sort();
        result.reverse();
    }
    else if(sort === "byValue")
    {
        result.sort(function(a,b) {return b[1] - a[1]});
    }
 
    var array = new google.visualization.DataTable();
   
    array.addColumn("string","Topping");
    array.addColumn("number","Slices");

    array.addRows(result);
   
    var options = {   is3D: true,
                      chartArea : { height:'80%',width:'95%' },
                      tooltip: { trigger: 'selection' },
                      width: 600,
                      legend: {position: 'right',labeledValueText: 'both'},
                      pieSliceText: 'none',
                      height: 450,
                      sliceVisibilityThreshold: threshold
                  };
                  
    var container = document.getElementById(id);
    var chart = new google.visualization.PieChart(document.getElementById(id));
    
    chart.draw(array,options);
}

// helper method in string for replacement
String.prototype.replaceAll = function(search, replacement) {
    var target = this;
    return target.replace(new RegExp("^"+search+"$", 'g'), replacement);
};

function replaceAll(str, map){
    for(key in map){
        str = str.replaceAll(key, map[key]);
    }
    return str;
}


function drawGoogleGermanyMap(data, el) {
   
    var id = rand(5);
   
    el.append("");
    el.append("<div id='"+id+"' class='googlemap'></div>");

    var result = [];

    var mapTextToCode = { 
        "Baden-Wurttemberg": "DE-BW",
        "Bayern": "DE-BY",
        "Berlin": "DE-BE",
        "Brandenburg": "DE-BB",
        "Bremen": "DE-HB",
        "Hamburg": "DE-HH",
        "Hessen": "DE-HE",
        "Mecklenburg-Vorpommern": "DE-MV",
        "Niedersachsen":"DE-NI",
        "Nordrhein-Westfalen": "DE-NW",
        "Rheinland-Pfalz": "DE-RP",
        "Saarland":"DE-SL",
        "Sachsen":"DE-SN",
        "Sachsen-Anhalt":"DE-ST",
        "Schleswig-Holstein":"DE-SH",
        "Thuringen":"DE-TH"
    };

    var mapTextToEnglish = { 
        "Baden-Wurttemberg": "Baden-W&uuml;rttemberg",
        "Bayern": "Bavaria",
        "Hessen": "Hesse",
        "Niedersachsen":"Lower Saxony",
        "Nordrhein-Westfalen": "North Rhine-Westphalia",
        "Rheinland-Pfalz": "Rhineland-Palatinate",
        "Sachsen":"Saxony",
        "Sachsen-Anhalt":"Saxony-Anhalt",
        "Thuringen":"Thuringia"
    };
   
    for(var i in data) {
        result.push([replaceAll(i, mapTextToCode), data [i], replaceAll(i, mapTextToEnglish)+": "+data[i]]);
    }

    var array = new google.visualization.DataTable();
   
    array.addColumn("string","Country");
    array.addColumn("number","Installations");
    array.addColumn({type: 'string', role: 'tooltip', p:{'html': true}});
    array.addRows(result);
    
    var options = {  region: 'DE',
                    colorAxis: {colors: ['#A7E7A7', '#278727']},
                    resolution: "provinces",
                    backgroundColor : 'lightblue',
                    tooltip: {isHtml: true},
                    width:800
                  };
   
    var chart = new google.visualization.GeoChart(document.getElementById(id));
    chart.draw(array,options);
}


function drawGoogleWorldMap(data, el) {
   
   var id = rand(5);
   
   el.append("");
   el.append("<div id='"+id+"' class='googlemap'></div>");

   var result = [];

   for(var i in data) {

        result.push([i, data[i].count, data[i].name+": "+data[i].count]);
   }

   var array = new google.visualization.DataTable();
   
   array.addColumn("string","Country");
   array.addColumn("number","Installations");
   array.addColumn({type: 'string', role: 'tooltip', p:{'html': true}});
   array.addRows(result);
   
   var options = {
                    colorAxis: {colors: ['#A7E7A7', '#A7E7A7']},
                    backgroundColor : 'lightblue',
                     tooltip: {isHtml: true},
                    legend: 'none',
                    width: 800
                 };
   
   var chart = new google.visualization.GeoChart(document.getElementById(id));
   chart.draw(array,options);
}

function drawGoogleEuroMap(data, el) {
   
   var id = rand(5);
   
   el.append("");
   el.append("<div id='"+id+"' class='googlemap'></div>");

   var result = [];
   
   for(var i in data) {
       result.push([i, data[i].count, data[i].name+": "+data[i].count]);
   }

   var array = new google.visualization.DataTable();
   
   array.addColumn("string","Country");
   array.addColumn("number","Installations");
   array.addColumn({type: 'string', role: 'tooltip'});
   array.addRows(result);
   
   var options = {  
                    region: '150',
                    colorAxis: {colors: ['#A7E7A7', '#A7E7A7']},
                    backgroundColor : 'lightblue',
                    legend: 'none',
                    width:800
                 };
   
   var chart = new google.visualization.GeoChart(document.getElementById(id));
   chart.draw(array,options);
}


function createModulTable(modules,models,table)
{
    var tbody = table.children("tbody");
   
    $.each(modules, function(module, moduleData) {
    
        if(moduleData.installations > 1) {
            
            var addon = "";
            
            if(module in models) 
            {
                addon = "<a href='#' class='model-link' module='"+module+"'>"+ Object.keys(models[module]).length+"</a>";
            }
            else
            {
                addon = "-";
            }
            
            tbody.append("<tr><td>"+module+"</td><td class='dt-body-center'>"+moduleData.installations+"</td><td class='dt-body-center'>"+moduleData.definitions+"</td><td class='dt-body-center'>"+addon+"</td></tr>");
        }
    });
    

    table.DataTable({
        order: [[ 1, "desc" ]],
        responsive: true,
        scrollCollapse: false,
        paging: true,
        lengthMenu: [ 10, 25, 50, 100, 200, 500 ],
        columnDefs: [ { "orderSequence": ['desc', 'asc'], "targets":1 },
                      { "orderSequence": ['desc', 'asc'], "targets":2 },
                      { "orderSequence": ['desc'], "targets":3 } ]
    });    

    $(document).on("click", "a.model-link", function (e) {
		var a = $(this);
        var moduleName = a.attr("module");
        var div = a.parent();
        
        $(generateModelsOverview(moduleName,models[moduleName])).dialog({
            modal: true,
            width:'auto',
            height:'auto',
            maxHeight: $(window).height(),
            open:function(){
                $(this).css({'max-height': $(window).height() - 200, 'overflow-y': 'auto'}); 
                
                $('.ui-widget-overlay').bind('click', function()
                { 
                    $("div.model-overview").dialog('close'); 
                }); 
            },
            buttons: { Close: function () {$(this).dialog("close");$(this).remove();} },
            close: function( event, ui ) {$(this).remove();}
        });
		
		return false;
	}); 
}

function convertHtmlEntities(str)
{
    return $("<div />").text(str).html();
}

function generateModelsOverview(moduleName, modelData)
{
    var str = '<div class="model-overview" title="Model variety for '+moduleName+'" module="'+moduleName+'">';
    
    var models = json2array(modelData);
    
    models.sort(function (a, b) {
        return a[0].toLowerCase().localeCompare(b[0].toLowerCase());
    });

    str += '<table class="block modelOverview"><tr><th>Model</th><th># of installations</th><th># of definitions</th></tr>'
    var cl = "odd";
    $.each(models, function(index, arr) {
        str += '<tr class="'+cl+'"><td class="modelName">'+convertHtmlEntities(arr[0])+'</td><td class="modelValue">'+arr[1].installations+'</td><td class="modelValue">'+arr[1].definitions+"</td></tr>";       
        cl = (cl == "odd" ? "even" : "odd");
    });
    
    str += "</table>";
    str += "</div>"

    return str;
}

function onSuccess(data, textStatus, jqXHR) {
       
    var div = $("div#overview");
    
    div.append("last submission: " + data.updated + " UTC<br>");
    div.append("created in: " + data.generated.toFixed(3) + " seconds<br>");
    div.append("number of submissions today: " + data.nodesToday + "<br>");
    div.append("number of submissions (last 12 months, used for statistics): " + data.nodes12 + "<br>");
    div.append("total number of submissions (since : " + data.started + "): "+data.nodesTotal+"<br><br>");
    div.append("You can help us increase the quality of FHEM statistics data. Please check <a href='https://fhem.de/commandref.html#fheminfo' target='_new'>fheminfo</a> command for details.");

    $("div.tabs").tabs();

    loadGoogleApi(function () {
        
        // draw google geo charts
        drawGoogleEuroMap(data.data.geo.countrycode, $("div#maptab-europe"));
        drawGoogleGermanyMap(data.data.geo.regionname.DE,$("div#maptab-germany"));
        drawGoogleWorldMap(data.data.geo.countrycode,$("div#maptab-world"));
        
        // draw google pie charts
        drawGooglePieChart(data.data.system.os, $("div#versiontab-os"), {"linux":"Linux","MSWin32":"Windows","darwin":"macOS","cygwin":"Cygwin","freebsd":"FreeBSD"}, "byValue",0 );
        drawGooglePieChart(data.data.system.perl, $("div#versiontab-perl"),false,undefined,0);
        
        drawGooglePieChart(data.data.system.age, $("div#versiontab-update"), {"0":"≤ 1 day", "7": "1 day - 1 week", "30": "1 week - 1 month", "180": "1 month - 6 months", "365": "6 months - 1 year", "999": "> 1 year"}, false);

        // create module table
        createModulTable(data.data.modules,data.data.models, $("table#module-table"));

        // show the result
        $("div#loading").hide(0, function () { 
            $("div#content").show();
        });
    });
}


function onError(jqXHR, textStatus,errorThrown) {
    
    console.log(jqXHR);
    $("div#right").append("<b>Error while loading JSON data</b>: "+jqXHR.status+" "+jqXHR.statusText+"<br><br>");
    
    if(jqXHR.responseText)
    {
        $("div#right").append("received: <pre>"+convertHtmlEntities(jqXHR.responseText)+"</pre>");
    }
    
    $("div#loading").hide(0);
}


// start the JSON request
$(function() {

    $.ajax({
        dataType: "json",
        url: "statistics2.cgi?type=json",
        success: onSuccess,
        error: onError,
        timeout: 30000
    });    
})

