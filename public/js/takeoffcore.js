// Make CORE.out() write to takeoff 'result' global variable http://github.com/scottbale/takeoff
(function(CORE){

    CORE.require = function(toImport){
        //nothing to do
    };
    CORE.out = function(output){
        result = result || '';
        result = result + '<p>' + output + '</p>';
    };

    return CORE;
}(CORE));
