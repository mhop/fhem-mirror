/*
 * ########################################################################################
 *
 * yaf-dialogs.js
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
// Initialisiert die Dialoge
function init_dialogs() {
	$("#dialog_addview").dialog({
		autoOpen: false,
		resizable: true,
		height: 300,
		width: 400,
		modal: true,
		buttons: {
			"Hinzufügen": function (event) {
				//console.log("before: " + views);
				$("#dialog_addview_loading").show();
				$.ajax({
					type: "GET",
					async: true,
					url: "../../ajax/global/addView",
					data: "name=" + $("#dialog_addview_name").val(),
					context: document.body,
					success: function (jsondata) {
						$("#dialog_addview").dialog("close");
						load_views(show_views);
						$("#dialog_addview_loading").hide();
						//console.log("after: " + views);
					}
				});
				$(this).dialog("close");
			},
			"Abbrechen": function () {
				$(this).dialog("close");
			}
		}
	});

	$("#dialog_deleteview").dialog({
		autoOpen: false,
		resizable: true,
		height: 300,
		width: 400,
		modal: true,
		buttons: {
			"Löschen": function (ui) {
				$.ajax({
					type: "GET",
					async: false,
					url: "../../ajax/global/deleteView",
					data: "id=" + delete_view_id,
					context: document.body,
					success: function (jsondata) {
						delete_tab(delete_view_id);
						$("#dialog_deleteview").dialog("close");
						$("#manageviews_tr_" + delete_view_id).remove();
					}
				});
				$(this).dialog("close");
			},
			"Abbrechen": function () {
				$(this).dialog("close");
			}
		}
	});

	$("#dialog_editview").dialog({
		autoOpen: false,
		resizable: true,
		height: 300,
		width: 400,
		modal: true,
		buttons: {
			"Speichern": function (ui) {
				//console.log("before: " + views);
				$("#dialog_editview_loading").show();
				$.ajax({
					type: "GET",
					async: true,
					url: "../../ajax/global/editView",
					data: "id=" + edit_view_id + "&name=" + $("#dialog_editview_name").val() + "&image=" + $("#dialog_editview_image").val(),
					context: document.body,
					success: function (jsondata) {
						load_views(show_views);
						$($("#manageviews_tr_" + edit_view_id).children().get(0)).text($("#dialog_editview_name").val());
						$("#dialog_editview_loading").hide();
						$("#dialog_editview").dialog("close");
					}
				});
				$(this).dialog("close");
			},
			"Abbrechen": function () {
				$(this).dialog("close");
			}
		}
	});

	$("#dialog_addwidget").dialog({
		autoOpen: false,
		resizable: true,
		height: 500,
		width: 600,
		modal: true,
		buttons: {
			"Schließen": function () {
				$(this).dialog("close");
			}
		},
		open: function (event, ui) {
			$("#dialog_addwidget_loading").show();
			$.ajax({
				type: "GET",
				async: true,
				url: "../../ajax/global/getWidgets",
				context: document.body,
				success: function (jsondata) {
					var widgets = jQuery.parseJSON(jsondata);
					$("#dialog_addwidget_table").html("<colgroup><col class=\"col1\"><col class=\"col2\"><col class=\"col3\"></colgroup>");
					if (widgets) {
						$.each(widgets, function (index, widget) {
							$("#dialog_addwidget_table").append("<tr><td>" + widget + "</td><td></td><td><button class=\"button_addwidget\" id=\"addwidget_" + widget + "\">&nbsp;</button></td></tr>");
						});
						$(".button_addwidget").button({
							icons: {
								primary: "ui-icon-circle-plus"
							},
							text: false
						});
						$(".button_addwidget").click(function (ui) {
							add_widget_name = $(ui.currentTarget).attr("id").substr(10);
							$("#dialog_addwidget_setup_widget").html(add_widget_name);
							$("#dialog_addwidget_setup").dialog("open");
							$("#dialog_addwidget_setup_loading").show();
							$.ajax({
								type: "GET",
								async: true,
								url: "../../ajax/widget/" + add_widget_name + "/get_addwidget_setup_html",
								context: document.body,
								success: function (html_result) {
									if (html_result != 0) {
										$("#dialog_addwidget_setup_form").html(html_result);
									} else {
										$("#dialog_addwidget_setup_form").html("Das Widget stellt keine Konfigurationsmöglichkeiten bereit!")
									}
									$("#dialog_addwidget_setup_loading").hide();
								}
							});
							//console.log("widget hinzufügen: " + add_widget_name)
							return false;
						});
					} else {
						console.log("keine Widgets vorhanden!")
					}
					$("#dialog_addwidget_loading").hide();
				}
			});
		}
	});

	$("#dialog_addwidget_setup").dialog({
		autoOpen: false,
		resizable: true,
		height: 350,
		width: 400,
		modal: true,
		buttons: {
			"Hinzufügen": function (event) {
				$("#dialog_addwidget_setup_loading").show();
				var attributes_array = new Array();
				$.ajax({
					type: "GET",
					async: false,
					url: "../../ajax/widget/" + add_widget_name + "/get_addwidget_prepare_attributes",
					context: document.body,
					success: function (js_result) {
						try {
							eval(js_result);
						}
						catch (exception) {
							console.log("exception in dialog_addwidget_setup dialog event");
						}
					}
				});
				//console.log(JSON.stringify(attributes_array));
				$.ajax({
					type: "GET",
					async: false,
					url: "../../ajax/global/addWidget",
					data: "view_id=" + current_view_id + "&widget=" + add_widget_name + "&attributes=" + JSON.stringify(attributes_array),
					context: document.body,
					success: function (widgetId) {
						// Position links oben x= 28 y = 69, muss auch in 01_YAF.pm in addWidget() Methode angepasst werden!
						add_widget(current_view_id, widgetId, add_widget_name, 28, 69, attributes_array);
						// Aktueller View Mode für alle Widgets aktualisiert
						switch_mode(view_mode);
					}
				});
				$("#dialog_addwidget_setup_loading").hide();

				$(this).dialog("close");
			},
			"Abbrechen": function () {
				$(this).dialog("close");
			}
		},
		open: function (event, ui) {
			//console.log("dialog widget hinzufügen geöffnet => inhalt laden");
		}
	});

	$("#dialog_deletewidget").dialog({
		autoOpen: false,
		resizable: true,
		height: 300,
		width: 400,
		modal: true,
		buttons: {
			"Löschen": function (ui) {
				var view_id = get_current_view_id();
				var widget_id = get_current_widget_id();
				//console.log("delete view " + view_id + " widget " + widget_id);
				$.ajax({
					type: "GET",
					async: false,
					url: "../../ajax/global/deleteWidget",
					data: "view_id=" + view_id + "&widget_id=" + widget_id,
					context: document.body,
					success: function (jsondata) {
						//console.log("widget deleted");
						$("#dialog_deletewidget").dialog("close");
						$("#widget_menue").hide();
						$("#widget_" + view_id + "_" + widget_id).remove();
					}
				});
				$(this).dialog("close");
			},
			"Abbrechen": function () {
				$(this).dialog("close");
			}
		}
	});

	$("#dialog_editwidget").dialog({
		autoOpen: false,
		resizable: true,
		height: 400,
		width: 500,
		modal: true,
		buttons: {
			"Speichern": function (ui) {				
				var keys = new Array();
				var vals = new Array();
				
				keys[0] = "id";
				vals[0] = current_widget_id;
				
				$('.input_edit_widget').each(function(i, obj) {
					keys[i+1] = obj.name;
					vals[i+1] = obj.value;
				});				
				
				$.ajax({
					type: "GET",
					async: false,
					url: "../../ajax/global/editWidget",
					data: "view_id="+current_view_id+"&widget_id="+current_widget_id+"&keys="+keys+"&vals="+vals,
					context: document.body,
					success: function (jsondata) {
						
					}
				});	
				$(this).dialog("close");
			},
			"Abbrechen": function () {
				$(this).dialog("close");
			}
		},
		open: function (event, ui) {
			$("#dialog_addwidget_loading").show();
			$.ajax({
				type: "GET",
				async: false,
				url: "../../ajax/widget/generic/get_editwidget_setup_html",
				data: "view_id="+current_view_id+"&widget_id="+current_widget_id,
				context: document.body,
				success: function (jsondata) {
					//var myform = jQuery.parseJSON(jsondata);

					$("#dialog_editwidget_setup_form").html(jsondata);
					$("#dialog_addwidget_loading").hide();
				}
			});
		}
	});

	$("#dialog_manageviews").dialog({
		autoOpen: false,
		resizable: true,
		height: 500,
		width: 600,
		modal: true,
		buttons: {
			"Schließen": function () {
				$(this).dialog("close");
			}
		},
		open: function (event, ui) {
			$("#dialog_manageviews-table").html("<colgroup><col class=\"col1\"><col class=\"col2\"><col class=\"col3\"></colgroup>");
			$.each(views, function (index, view) {
				$("#dialog_manageviews-table").append("<tr id=\"manageviews_tr_" + view[0] + "\"><td>" + view[1] + "&nbsp;&nbsp;&nbsp;<img width=\"40\" src=\"" + view[2] + "\" id=\"image_edit_" + view[0] + "\" /></td><td><button id=\"button_edit_" + view[0] + "\" class=\"button_edit\">&nbsp;</button></td><td><button class=\"button_delete\" id=\"button_edit_" + view[0] + "\">&nbsp;</button></td></tr>" );
			});
			$(".button_edit").button({
				icons: {
					primary: "ui-icon-pencil"
				},
				text: false
			});
			$(".button_delete").button({
				icons: {
					primary: "ui-icon-trash"
				},
				text: false
			});
			$(".button_delete").click(function (ui) {
				var sichtName = $(ui.currentTarget.parentNode.parentNode.firstChild).html();
				delete_view_id = $(ui.currentTarget).attr("id").substr(12);
				$("#label_deleteview").html(sichtName);
				$("#dialog_deleteview").dialog("open");
				return false;
			});
			$(".button_edit").click(function (ui) {
			
				edit_view_id = $(ui.currentTarget).attr("id").substr(12);
				
				$.each(views, function (index, view) { //this is quite ineffective and should be redone
					if(view[0] == edit_view_id) {
						edit_view_name = view[1];
						edit_view_image = view[2];
					}
				});			
				
				$("#dialog_editview_name").val(edit_view_name);
				$("#dialog_editview_image").val(edit_view_image);
				$("#dialog_editview").dialog("open");
				return false;
			});
		}
	});

	$("#dialog_settings").dialog({
		autoOpen: false,
		resizable: true,
		height: 500,
		width: 600,
		modal: true,
		buttons: {
			"Speichern": function () {
				$("#dialog_settings_loading").show();
				//console.log("update widget refresh interval");
				$.ajax({
					type: "GET",
					async: true,
					url: "../../ajax/global/setRefreshTime",
					data: "interval=" + $("#dialog_settings_intervall").val(),
					context: document.body,
					success: function () {
						refreshTime = $("#dialog_settings_intervall").val();
						$("#dialog_settings_loading").hide();
						$("#dialog_settings").dialog("close");
					}
				});
				$(this).dialog("close");
			},
			"Abbrechen": function () {
				$(this).dialog("close");
			}
		},
		open: function (event, ui) {
			//console.log("dialog settings opened");
			$("#dialog_settings_loading").show();
			$.ajax({
				type: "GET",
				async: true,
				url: "../../ajax/global/getRefreshTime",
				data: "interval=" + $("#dialog_settings_intervall").val(),
				context: document.body,
				success: function (refreshInterval) {
					$("#dialog_settings_intervall").val(refreshInterval);
					$("#dialog_settings_loading").hide();
				}
			});
		}
	});
}
