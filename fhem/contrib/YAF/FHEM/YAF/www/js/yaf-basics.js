/*
 * ########################################################################################
 *
 * yaf-basics.js
 *
 * YAF - Yet Another Floorplan
 * FHEM Projektgruppe Hochschule Karlsruhe, 2013
 * Markus Mangei, Daniel Weisensee, Prof. Dr. Peter A. Henning
 *
 * ########################################################################################
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * ########################################################################################
 */
function get_current_view_id() {
	return current_view_id;
}

function get_current_widget_id() {
	return current_widget_id;
}

// Ändert den Modus der Oberfläche
// mode: id des Modus
function switch_mode(new_mode) {
	view_mode = new_mode;
	if (new_mode == 0) {
		// Live Modus
		$(".widgets").draggable("disable");
	} else if (new_mode == 1) {
		// Positionierungsmodus
		$(".widgets").draggable("enable");
	}
}

// Timer für den Reload
// Wenn startIntervall = 1 ist, dann wird die Schleife gestartet,
// ansonsten ist es ein einmaliger aufruf
function refreshWidgets() {
	$.each(widgets, function (index, widget) {
		update_widget(widget[0], widget[1], widget[2])
	});
	setTimeout(function () {
		refreshWidgets();
	},
	refreshTime * 1000);
}

function init_RefreshWidgets() {
	$.ajax({
		async: true,
		url: "../../ajax/global/getRefreshTime",
		context: document.body,
		success: function (_refreshTime) {
			refreshTime = _refreshTime;
			refreshWidgets();
		}
	});
}

// Läd die Sichten über AJAX vom Server.
// callback: wird aufgerufen, wenn der Server geantwortet hat
function load_views(callback) {
	//console.log("called load_views()");
	$.ajax({
		async: true,
		url: "../../ajax/global/getViews",
		context: document.body,
		success: function (jsondata) {
			views = jQuery.parseJSON(jsondata);
			//console.log(views);
			if (callback) {
				callback();
			}
		}
	});
	return;
}

// Fügt eine neue Sicht zu den Tabs hinzu.
// id: Id der Sicht
// name: Name der Sicht
function add_tab(id, name) {
	//console.log("called add_tab()");
	// Neues Div nur erzeugen, wenn es noch keins mit der entsprechenden Id gibt
	if ($("#tabs-" + id).length <= 0) {
		$("#tabs").append("<div id=\"tabs-" + id + "\" class=\"loaded tab\"></div>");
	}
	$("#views").append("<li id=\"tabs_li-" + id + "\"><a href=\"#tabs-" + id + "\">" + name + "</a></li>");
	$("#tabs").tabs("refresh");
	return;
}

// Löscht eine Sicht aus den Tabs.
// Das <div> sowie der <li> Eintrag werden gelöscht.
// id: Id der zu löschenden Sicht
function delete_tab(id) {
	//	Kann noch optimiert werden!
	//console.log("called delete_tab()");
	$("#tabs-" + id).remove();
	$("#tabs_li-" + id).remove();
	load_views(show_views);
	return;
}

// Zeigt alle Tabs neu an.
// Zuerst werden alle Tabs gelöscht und anschließend neu anzeigen.
function show_views() {
	//console.log("called show_views()");
	$("#views").html("");

	if (views.length == 0) {
		$('#views').hide();
		$('#tabs_error').html("Es wurden keine Sichten gefunden!");
		$('#tabs_error').show();
	} else {
		$('#tabs_error').hide();
		$('#views').show();
		var selected_view_id = get_current_view_id();
		var selected = 0;
		var minId = 999;
		$.each(views, function (index, view) {
			add_tab(view[0], view[1]);
			if (selected_view_id == view[0]) {
				$('#tabs').tabs("select", "#tabs-" + view[0]);
				selected = 1;
			}
			if (view[0] < minId) {
				minId = view[0];
			}
		});
		if (! selected) {
			$('#tabs').tabs("select", "#tabs-" + minId);
		}
	}

	return;
}

// Zeigt ein neues Hintergrundbild in einer bestimmten Sicht an.
// view_id: Die Sicht, in der das Hintergrundbild eingefügt werden soll
// file: Pfad und Dateiname der Grafik
// x_pos: x Positon
// y_pos: y Position
function add_background_image(view_id, file, x_pos, y_pos) {
	$("#tabs-" + view_id).append("<img src=\"" + file + "\" />");
}

function update_widget(name, view_id, widget_id) {
	//console.log("update_widget " + name);
	try {
		eval(name + "_update_widget(" + view_id + ", " + widget_id + ")");
	}
	catch (exception) {
		console.log("Error in update_widget()");
	}
}

// Zeigt ein neues Widget in einer bestimmten Sicht an.
// view_id: Die Sicht, in der das Hintergrundbild eingefügt werden soll
// name: Typ des Widgets
// x_pos: x Positon
// y_pos: y Position
// attr_array: Ein Array mit den Attributen des Widgets.
function add_widget(view_id, widget_id, name, x_pos, y_pos, attr_array) {
	var widget_html = "";
	$.ajax({
		type: "GET",
		async: false,
		url: "../../ajax/widget/" + name + "/getwidget_html",
		context: document.body,
		success: function (result) {
			widget_html = result;
		}
	});
	$("#tabs-" + view_id).append("<div id=\"widget_" + view_id + "_" + widget_id + "\" class=\"widgets widget_" + name + "\" style=\"left: " + x_pos + "px; top: " + y_pos + "px;\">" + widget_html + "</div>");

	update_widget(name, view_id, widget_id);

	$("#widget_" + view_id + "_" + widget_id).click(function () {
		if (view_mode == 0) {
			try {
				eval(name + "_on_click(" + view_id + ", " + widget_id + ")");
			}
			catch (exception) {
				console.log("Error in on_click()");
			}
		} else if (view_mode == 1) {
			if (! widgetWasMoved) {
				$("#widget_menue").show();
				current_widget_id = widget_id;
				var top = $("#widget_" + view_id + "_" + widget_id).position().top;
				var left = $("#widget_" + view_id + "_" + widget_id).position().left;
				// Nach links anzeigen
				var offsetLeft = $("#widget_" + view_id + "_" + widget_id).width();
				var positionLeft = left + offsetLeft - 10;
				var positionTop = top - 23;
				$("#widget_menue").css("top", positionTop);
				$("#widget_menue").css("left", positionLeft);
				setTimeout(function () {
					if (close_widget_menue) {
						$("#widget_menue").hide();
					}
				},
				2500);
			}
		}
	});

	$("#widget_" + view_id + "_" + widget_id).draggable({
		containment: "parent",
		start: function (event, ui) {
			close_widget_menue = true;
			$("#widget_menue").hide();
		},
		stop: function (event, ui) {
			widgetWasMoved = true;
			setTimeout(function () {
				widgetWasMoved = false;
			},
			500);
			// Neue Position des Widget speichern. Kommastellen werden abgeschnitten.
			x_pos = parseInt(ui.position.left);
			y_pos = parseInt(ui.position.top);
			widget_id = $(event.target).attr("id").split("_")[2];
			view_id = $(event.target).attr("id").split("_")[1];
			//console.log("view-id: " + get_current_view_id() + " widget-id: " + widget_id + " x-pos: " + x_pos + " y-pos: " + y_pos);
			$.ajax({
				type: "GET",
				async: true,
				url: "../../ajax/global/setWidgetPosition",
				data: "view_id=" + view_id + "&widget_id=" + widget_id + "&x_pos=" + x_pos + "&y_pos=" + y_pos,
				context: document.body,
				success: function (jsondata) {
					//console.log("Widget Position geändert: " + jsondata)
				}
			});
		}
	});

	// widget in Widgetliste einfügen
	var widget = new Array(name, get_current_view_id(), widget_id);
	widgets[widgets.length] = widget;
}

// Behandelt das öffnen eines Tabs
// Entweder der Inhalt wurde bereits geladen, oder er muss über
// Ajax nachgeladen werden.
function activate_tab(view_id) {
	if (! $("#tabs-" + view_id).hasClass("isLoaded")) {
		current_view_id = view_id;
		//console.log("activate tab: " + view_id);
		//console.log("load widgets");
		$("#tabs-" + view_id).html("");
		// Speichern, dass view bereits geladen wurde
		$("#tabs-" + view_id).addClass("isLoaded");
		$("#tabs-" + view_id).html("");
		$.ajax({
			async: false,
			url: "../../ajax/global/getView",
			data: "id=" + view_id,
			context: document.body,
			success: function (jsondata) {
				var view_data = jQuery.parseJSON(jsondata);
				// background images laden
				if (view_data.backgrounds) {
					$.each(view_data.backgrounds, function (index, background) {
						add_background_image(view_id, background.img_url, background.x_pos, background.y_pos);
					});
				} else {
					console.log("keine Hintergrundbilder vorhanden!");
				}
				// widgets laden
				if (view_data.widgets) {
					$.each(view_data.widgets, function (index, widget) {
						widget_x_pos = widget.x_pos;
						widget_y_pos = widget.y_pos;
						widget_name = widget.name;
						widget_id = widget.id;
						add_widget(view_id, widget_id, widget_name, widget_x_pos, widget_y_pos, 0);
					});
					// Aktueller View Mode für alle Widgets aktualisiert
					switch_mode(view_mode);
				} else {
					console.log("keine Widgets vorhanden!");
				}
			}
		});
	} else {
		current_view_id = view_id;
		//console.log("switch to activated tab: " + view_id);
	}

	return;
}

// Initialisiert die Tabs. Diese Funktion muss nur einmal aufgerufen werden.
// Sobald das Tab gewechselt wird, wird die Funktion activate_tab(id)
// aufgerufen.
function init_tabs() {
	$("#tabs").tabs({
		activate: function (event, ui) {
			activate_tab(ui.newPanel.selector.substr(6));
		},
		create: function (event, ui) {
			//activate_tab(ui.panel.selector.substr(6));
		}
	});
	$("#tabs").resizable({
		containment: $(".widgets")
	});
}

// Initialisiert das Menü.
function init_menue() {
	$("#button_back").button({
		icons: {
			secondary: "ui-icon-circle-arrow-w"
		}
	});

	$("#button_addview").button({
		icons: {
			secondary: "ui-icon-plusthick"
		}
	});

	$("#button_manageviews").button({
		icons: {
			secondary: "ui-icon-plusthick"
		}
	});

	$("#button_addwidget").button({
		icons: {
			secondary: "ui-icon-plusthick"
		}
	});

	$("#button_managewidgets").button({
		icons: {
			secondary: "ui-icon-plusthick"
		}
	});

	$("#button_settings").button({
		icons: {
			secondary: "ui-icon-pencil"
		}
	});

	$("#widget_menue_edit").button({
		icons: {
			secondary: "ui-icon-pencil"
		}
	});

	$("#widget_menue_delete").button({
		icons: {
			secondary: "ui-icon-trash"
		}
	});

	$("#button_editview").buttonset();

	$("#button_saveconfig").button({
		icons: {
			secondary: "ui-icon-disk"
		}
	});
}

// Initialisiert die Handler
function init_handlers() {
	$("#button_back").click(function () {
		window.location.href = "../../../../fhem";
		return false;
	});

	$("#button_settings").click(function () {
		$("#dialog_settings").dialog("open");
		return false;
	});

	$("#button_addview").click(function () {
		$("#dialog_addview").dialog("open");
		return false;
	});

	$("#button_manageviews").click(function () {
		$("#dialog_manageviews").dialog("open");
		return false;
	});

	$("#button_addwidget").click(function () {
		$("#dialog_addwidget").dialog("open");
		return false;
	});

	$("#button_switchmode_0").click(function () {
		if (view_mode != 0) {
			switch_mode(0);
		}
	});

	$("#button_switchmode_1").click(function () {
		if (view_mode != 1) {
			switch_mode(1);
		}
	});

	$("#button_saveconfig").click(function () {
		$.ajax({
			type: "GET",
			async: true,
			url: "../../ajax/global/saveconfig",
			context: document.body,
			success: function (jsondata) {
				$("#button_saveconfig").button({
					icons: {
						secondary: "ui-icon-check"
					}
				});
				var timeoutID = window.setTimeout(function () {			
					$("#button_saveconfig").button({
						icons: {
							secondary: "ui-icon-disk"
						}
					});
				},3000);
			}
		});		
	});

	$("#widget_menue_delete").click(function () {
		$("#label_deletewidget").html(get_current_widget_id());
		$("#dialog_deletewidget").dialog("open");
	});

	$("#widget_menue_edit").click(function () {
		$("#label_editwidget").html(get_current_widget_id());
		$("#dialog_editwidget").dialog("open");
		$("#widget_menue").hide();
		close_widget_menue = true;
	});

	$("#widget_menue").mouseenter(function () {
		close_widget_menue = false;
	});

	$("#widget_menue").mouseleave(function () {
		close_widget_menue = true;
		$("#widget_menue").hide();
	});
}