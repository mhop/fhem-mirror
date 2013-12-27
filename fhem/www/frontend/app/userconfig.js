/**
 * This is the user configuration file for the frontend.
 * You can set your own parameters here, e.g. to set how the charting should
 * handle non numeric values
 */
FHEM = {};

FHEM.userconfig = {
        
        // Here you can set how non numeric values like "on" or "off" should be interpreted in the charts
        // you can add your own specific parameter here if needed and give it a numeric value of your choice, e.g. 
        // "an": "100",
        // "aus": "50"
        chartkeys: {
            "on": "1",
            "off": "0",
            "open": "10",
            "closed": "1"
        }
};