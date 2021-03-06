package er.rest;

import com.webobjects.eocontrol.EOClassDescription;
import com.webobjects.eocontrol.EOEditingContext;
import com.webobjects.eocontrol.EOEnterpriseObject;
import com.webobjects.foundation.NSMutableDictionary;
import com.webobjects.foundation._NSUtilities;

/**
 * The delegate interface used to convert objects to and from request nodes.
 * 
 * @author mschrag
 */
public interface IERXRestDelegate {
	/**
	 * Sets the editing context fort his rest delegate (which might not be necessary, but EO delegates require it).
	 * 
	 * @param editingContext
	 *            the editing context for this delegate
	 */
	public void setEditingContext(EOEditingContext editingContext);

	/**
	 * Returns the primary key for the specified object.
	 * 
	 * @param obj
	 *            the object to return a pk for
	 * @return the primary key of the object
	 */
	public Object primaryKeyForObject(Object obj);

	/**
	 * Creates a new instance of the entity.
	 * 
	 * @param entity
	 *            the entity
	 * @return a new instance of the entity
	 */
	public Object createObjectOfEntityWithID(EOClassDescription entity, Object id);

	/**
	 * Returns the object with the given entity and ID.
	 * 
	 * @param entity
	 *            the entity
	 * @param id
	 *            the ID of the object
	 * @return the object with the given entity and ID
	 */
	public Object objectOfEntityWithID(EOClassDescription entity, Object id);

	/**
	 * This API will likely change. Override if you have to for now, but I'm not
	 * sure if it makes more sense to return an array of pk classes, a map of
	 * pk to pk class, this boolean, or an array of pk attribute names. If we
	 * return pk names, we could probably get rid of primaryKeyForObject, or
	 * at least fully implement it in ERXAbstractRestDelegate, but I don't
	 * want to fully commit to this API yet. In the meantime, this at least
	 * provides a stapgap for automatic registration. 
	 *  
	 * @param classDescription the class description in question
	 * @return whether or not the given class description has numeric pks
	 */
	public boolean __hasNumericPrimaryKeys(EOClassDescription classDescription);

	/**
	 * A Factory for creating IERXRestDelegates. Right now it's just hard-coded, but this is being added for a later
	 * extension point.
	 * 
	 * @author mschrag
	 */
	public static class Factory {
		private static NSMutableDictionary<String, Class<? extends IERXRestDelegate>> _delegates = new NSMutableDictionary<String, Class<? extends IERXRestDelegate>>();
		private static Class<? extends IERXRestDelegate> _defaultDelegate = ERXEORestDelegate.class;
		
		/**
		 * Sets the default rest delegate to use when no other can be found. The default is ERXEORestDelegate. 
		 * 
		 * @param defaultDelegate the default delegate to use
		 */
		public static void setDefaultDelegateClass(Class<? extends IERXRestDelegate> defaultDelegate) {
			IERXRestDelegate.Factory._defaultDelegate = defaultDelegate;
		}
		
		/**
		 * Registers a rest delegate for the given entity name.
		 * 
		 * @param delegateClass
		 *            the delegate class to register
		 * @param entityName
		 *            the entity name to register for
		 */
		public static void setDelegateForEntityNamed(Class<? extends IERXRestDelegate> delegateClass, String entityName) {
			_delegates.setObjectForKey(delegateClass, entityName);
		}
		
		/**
		 * Registers a rest delegate for the given entity name.
		 * 
		 * @param delegateClass
		 *            the delegate class to register
		 * @param entityName
		 *            the entity name to register for
		 */
		public static void setDelegateForEntityNamed(Class<? extends IERXRestDelegate> delegateClass, String entityName, Class<?> clazz) {
			_delegates.setObjectForKey(delegateClass, entityName);
			ERXRestClassDescriptionFactory.registerClass(clazz);
		}

		/**
		 * Returns a rest delegate for the given entity name.
		 * 
		 * @param entityName
		 *            the name o the entity to lookup
		 * @param editingContext
		 *            the current editingcontext
		 * @return a rest delegate
		 */
		public static IERXRestDelegate delegateForEntityNamed(String entityName, EOEditingContext editingContext) {
			IERXRestDelegate delegate;
			Class<? extends IERXRestDelegate> delegateClass = _delegates.objectForKey(entityName);
			if (delegateClass == null) {
				Class<?> possibleDelegateClass = _NSUtilities.classWithName(entityName + "RestDelegate");
				if (possibleDelegateClass != null) {
					delegateClass = possibleDelegateClass.asSubclass(IERXRestDelegate.class);
				}
			}

			if (delegateClass != null) {
				try {
					delegate = delegateClass.newInstance();
				}
				catch (Throwable t) {
					throw new RuntimeException("Failed to create a delegate for the entity '" + entityName + "'.", t);
				}
			}
			else {
				try {
					delegate = IERXRestDelegate.Factory._defaultDelegate.newInstance();
				}
				catch (Exception e) {
					throw new RuntimeException("Failed to create the rest delegate '" + _defaultDelegate + ".", e);
				}
			}
			delegate.setEditingContext(editingContext);
			return delegate;
		}

		/**
		 * Returns the entity name for the given object.
		 * 
		 * @param obj the object to return an entity name for
		 * @return the entity name for the given object
		 */
		public static String entityNameForObject(Object obj) {
			String entityName;
			EOEditingContext editingContext;
			if (obj instanceof EOEnterpriseObject) {
				entityName = ((EOEnterpriseObject)obj).entityName();
				editingContext = ((EOEnterpriseObject)obj).editingContext();
			}
			else {
				entityName = obj.getClass().getSimpleName();
				editingContext = null;
			}
			return entityName;
		}
	}
}