/*
 * Copyright (C) NetStruxr, Inc. All rights reserved.
 *
 * This software is published under the terms of the NetStruxr
 * Public Software License version 0.5, a copy of which has been
 * included with this distribution in the LICENSE.NPL file.  */

package er.bugtracker;
import com.webobjects.appserver.*;
import com.webobjects.directtoweb.*;
import com.webobjects.eocontrol.*;
import com.webobjects.eoaccess.*;

public class EditOwner extends D2WComponent {

    public EditOwner(WOContext c) {
        super(c);
    }
    
    /** @TypeInfo People */
    public EOEnterpriseObject localOriginator() {
        if(object() != null && ((Bug)object()).originator() != null)
            return EOUtilities.localInstanceOfObject(session().defaultEditingContext(),
                                                 ((Bug)object()).originator());
        return null;
    }
}