export default `/**
* Adds a lookup relation or 'dome insert' to a record.
* @public
* @example
* Data Sourced Value:
*  relationship("relationship_name__r", "externalID on related object", dataSource("path"))
* Fixed Value:
*  relationship("relationship_name__r", "externalID on related object", "hello world")
* @function
* @param {string} relationshipName - \`__r\` relationship field on the record.
* @param {string} externalId - Salesforce ExternalID field.
* @param {string} dataSource - resolvable source.
* @returns {object}
*/
export function relationship(relationshipName: string, externalId: string, dataSource: string): object;
/**
* Executes an operation.
* @function
* @param {Operation} operations - Operations
* @returns {State}
*/
export function execute(...operations: Operation): State;
/**
* Flattens an array of operations.
* @example
* steps(
*   createIf(params),
*   update(params)
* )
* @function
* @returns {Array}
*/
export function steps(...operations: any[]): any[];
/**
* Outputs basic information about available sObjects.
* @public
* @example
* describeAll()
* @function
* @param {State} state - Runtime state.
* @returns {State}
*/
export const describeAll: any;
/**
* Outputs basic information about an sObject to \`STDOUT\`.
* @public
* @example
* describe('obj_name')
* @function
* @param {String} sObject - API name of the sObject.
* @param {State} state - Runtime state.
* @returns {State}
*/
export const describe: any;
/**
* Retrieves a Salesforce sObject(s).
* @public
* @example
* retrieve('ContentVersion', '0684K0000020Au7QAE/VersionData');
* @function
* @param {String} sObject - The sObject to retrieve
* @param {String} id - The id of the record
* @param {Function} callback - A callback to execute once the record is retrieved
* @param {State} state - Runtime state
* @returns {State}
*/
export const retrieve: any;
/**
* Execute an SOQL query.
* Note that in an event of a query error,
* error logs will be printed but the operation will not throw the error.
* @public
* @example
* query(\`SELECT Id FROM Patient__c WHERE Health_ID__c = '\$\{state.data.field1\}'\`);
* @function
* @param {String} qs - A query string.
* @param {State} state - Runtime state.
* @returns {Operation}
*/
export const query: any;
/**
* Create and execute a bulk job.
* @public
* @example
* bulk('Patient__c', 'insert', { failOnError: true, pollInterval: 3000, pollTimeout: 240000 }, state => {
*   return state.data.someArray.map(x => {
*     return { 'Age__c': x.age, 'Name': x.name }
*   })
* });
* @function
* @param {String} sObject - API name of the sObject.
* @param {String} operation - The bulk operation to be performed
* @param {Object} options - Options passed to the bulk api.
* @param {Function} fun - A function which takes state and returns an array.
* @param {State} state - Runtime state.
* @returns {Operation}
*/
export const bulk: any;
/**
* Delete records of an object.
* @public
* @example
* destroy('obj_name', [
*  '0060n00000JQWHYAA5',
*  '0090n00000JQEWHYAA5
* ], { failOnError: true })
* @function
* @param {String} sObject - API name of the sObject.
* @param {Object} attrs - Array of IDs of records to delete.
* @param {Object} options - Options for the destroy delete operation.
* @param {State} state - Runtime state.
* @returns {Operation}
*/
export const destroy: any;
/**
* Create a new object.
* @public
* @example
* create('obj_name', {
*   attr1: "foo",
*   attr2: "bar"
* })
* @function
* @param {String} sObject - API name of the sObject.
* @param {Object} attrs - Field attributes for the new object.
* @param {State} state - Runtime state.
* @returns {Operation}
*/
export const create: any;
/**
* Create a new object if conditions are met.
* @public
* @example
* createIf(true, 'obj_name', {
*   attr1: "foo",
*   attr2: "bar"
* })
* @function
* @param {boolean} logical - a logical statement that will be evaluated.
* @param {String} sObject - API name of the sObject.
* @param {Object} attrs - Field attributes for the new object.
* @param {State} state - Runtime state.
* @returns {Operation}
*/
export const createIf: any;

/**
* Upsert an object.
* @public
* @example
* upsert('obj_name', 'ext_id', {
*   attr1: "foo",
*   attr2: "bar"
* })
* @function
* @param {String} sObject - API name of the sObject.
* @magic sObject $.children[?(!@.meta.system)].name
* @param {String} externalId - ID.
* @magic externalId $.children[?(@.name=="{{args.sObject}}")].children[?(@.meta.externalId)].name
* @param {Object} attrs - Field attributes for the new object.
* @param {State} state - Runtime state.
* @magic attrs $.children[?(@.name=="{{args.sObject}}")].children[?(!@.meta.externalId)]
* @returns {Operation}
*/
export function upsert(sObject: string, externalId: string, attrs?: object, state?: any): Operation;

/**
* Upsert if conditions are met.
* @public
* @example
* upsertIf(true, 'obj_name', 'ext_id', {
*   attr1: "foo",
*   attr2: "bar"
* })
* @function
* @param {boolean} logical - a logical statement that will be evaluated.
* @param {String} sObject - API name of the sObject.
* @param {String} externalId - ID.
* @param {Object} attrs - Field attributes for the new object.
* @param {State} state - Runtime state.
* @returns {Operation}
*/
export const upsertIf: any;
/**
* Update an object.
* @public
* @example
* update('obj_name', {
*   attr1: "foo",
*   attr2: "bar"
* })
* @function
* @param {String} sObject - API name of the sObject.
* @param {Object} attrs - Field attributes for the new object.
* @param {State} state - Runtime state.
* @returns {Operation}
*/
export const update: any;
/**
* Get a reference ID by an index.
* @public
* @example
* reference(0)
* @function
* @param {number} position - Position for references array.
* @param {State} state - Array of references.
* @returns {State}
*/
export const reference: any;
export { axios };
export type State = {
   /**
    * JSON Data.
    */
   data: object;
   /**
    * History of all previous operations.
    */
   references: Array<Reference>;
};
export type Operation = Function;
import axios from "axios";
export { alterState, arrayToString, beta, chunk, combine, dataPath, dataValue, dateFns, each, expandReferences, field, fields, fn, http, humanProper, index, join, jsonValue, lastReferenceValue, map, merge, referencePath, scrubEmojis, source, sourceValue, toArray } from "@openfn/language-common";
`;
