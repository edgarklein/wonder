
import com.webobjects.appserver.*;
import com.webobjects.directtoweb.D2WPage;

import er.ajax.AjaxUtils;

// Generated by the WOLips Templateengine Plug-in at Jun 25, 2008 11:37:46 AM
public class Home extends D2WPage {
    public Home(WOContext context) {
        super(context);
    }
    
    // R/R
    @Override
	public void appendToResponse(WOResponse response, WOContext context) {
    	super.appendToResponse(response, context);
		if (((Session) session()).isWebObjectsTheme()) { 
			AjaxUtils.addStylesheetResourceInHead(context, response, "app", "WebObjects.css");
		} else AjaxUtils.addStylesheetResourceInHead(context, response, "app", "Neutral.css");
    }
}