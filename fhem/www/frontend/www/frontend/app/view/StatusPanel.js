/**
 * A Panel containing FHEM status information
 */
Ext.define('FHEM.view.StatusPanel', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.statuspanel',
    name: 'statuspanel',
    /**
     * 
     */
    title: 'FHEM Status',
    
    /**
     * 
     */
    region: 'center',
    
    /**
     * 
     */
    autoScroll: true,
    
    /**
     * init function
     */
    initComponent: function() {
        
        var me = this;
        
        me.items = [
            {
                xtype: 'toolbar',
                ui: 'footer',
                enableOverflow: true,
                items: [
                        {
                            xtype: 'numberfield',
                            fieldLabel: "Width",
                            labelWidth: 30,
                            width: 120,
                            padding: '0 20px 0 5px',
                            name: 'previewchartwidth',
                            value: (FHEM.userconfig.previewchartsconfig &&
                                    FHEM.userconfig.previewchartsconfig.width) ?
                                    FHEM.userconfig.previewchartsconfig.width : 459
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: "Height",
                            labelWidth: 30,
                            width: 120,
                            padding: '0 20px 0 5px',
                            name: 'previewchartheight',
                            value: (FHEM.userconfig.previewchartsconfig &&
                                    FHEM.userconfig.previewchartsconfig.height) ?
                                    FHEM.userconfig.previewchartsconfig.height : 280
                        },
                        {
                            text: 'Apply Size',
                            name: 'applypreviewchartsize'
                        },
                        {
                            xtype: 'tbseparator'
                        },
                        {
                            xtype: 'checkbox',
                            fieldLabel: "Auto Update?",
                            labelWidth: 70,
                            name: 'autoupdatecheckbox',
                            checked: (FHEM.userconfig.previewchartsconfig &&
                                      FHEM.userconfig.previewchartsconfig.autoUpdate === false) ?
                                      false : true
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: "Update Interval",
                            labelWidth: 80,
                            name: 'updateinterval',
                            width: 150,
                            minValue: 60,
                            editable: false,
                            value: (FHEM.userconfig.previewchartsconfig &&
                                    FHEM.userconfig.previewchartsconfig.updateInterval) ?
                                    FHEM.userconfig.previewchartsconfig.updateInterval : 120
                        },
                        {
                            xtype: 'text',
                            name: 'countdowntext',
                            width: 100,
                            counter: (FHEM.userconfig.previewchartsconfig &&
                                       FHEM.userconfig.previewchartsconfig.updateInterval) ?
                                       FHEM.userconfig.previewchartsconfig.updateInterval - 2 : 118,
                            text: 'Updates disabled',
                            disabled: (FHEM.userconfig.previewchartsconfig &&
                                       FHEM.userconfig.previewchartsconfig.autoUpdate === false) ?
                                            true : false
                        },
                        {
                            text: 'Reload all now!',
                            name: 'reloadallpreviews',
                            cls:'x-btn-default-small'
                        },
                        {
                            text: 'Save configuration',
                            name: 'savepreviewchartsconfig'
                        }
                    ]
             },
             {
                xtype: 'panel',
                name: 'previewchartcontainer',
                layout: 'column',
                html: 'This panel gives you an overview of your Charts by displaying them as small windows here.<br>' + 
                       'To add Charts to this Overview, simply drop some into the folder "StatusRoom" which you<br>' +
                       'can find in the tree on the left side.<br>' +
                       'Add as much charts as you want, configure their size and update options and save your<br>' +
                       'settings by clicking on "Save configuration".<br>' +
                       'The first time you add a new chart you need to reload it, before you can see it!'
             }
        ];
        me.callParent(arguments);
    }
});
