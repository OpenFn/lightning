export default `
// index.d.ts
export type Dhis2Attribute = {
  /**
   * The attribute id
   * @lookup $.children.attributes[*]
   */
  attribute: string;

  value: any;
};

export type Dhis2Data = {
  /**
   * The id of an organisation unit
   * @lookup $.children.orgUnits[*]
   */
  orgUnit?: string;

  /**
   * Tracked instance id
   */
  trackedEntityInstance?: string;

  /**
   * Tracked instance type
   * @lookup $.children.trackedEntityTypes[*]
   */
  trackedEntityType?: string;

  /**
   * List of attributes
   */
  attributes?: Dhis2Attribute[];
};

// Adaptor.d.ts
/**
 * Execute a sequence of operations.
 * Wraps \`language-common/execute\`, and prepends initial state for DHIS2.
 * @example
 * execute(
 *   create('foo'),
 *   delete('bar')
 * )(state)
 * @function
 * @param {Operations} operations - Operations to be performed.
 * @returns {Operation}
 */
export function execute(...operations: Operations): Operation;
/**
 * Create a record
 * @public
 * @function
 * @param {string} resourceType - Type of resource to create. E.g. \`trackedEntityInstances\`, \`programs\`, \`events\`, ...
 * @paramlookup resourceType $.children.resourceTypes[*]
 * @param {Dhis2Data} data - Data that will be used to create a given instance of resource. To create a single instance of a resource, \`data\` must be a javascript object, and to create multiple instances of a resources, \`data\` must be an array of javascript objects.
 * @param {Object} [options] - Optional \`options\` to define URL parameters via params (E.g. \`filter\`, \`dimension\` and other import parameters), request config (E.g. \`auth\`) and the DHIS2 apiVersion.
 * @param {function} [callback] - Optional callback to handle the response
 * @returns {Operation}
 * @example <caption>a program</caption>
 * create('programs', {
 *   name: 'name 20',
 *   shortName: 'n20',
 *   programType: 'WITHOUT_REGISTRATION',
 * });
 * @example <caption>an event</caption>
 * create('events', {
 *   program: 'eBAyeGv0exc',
 *   orgUnit: 'DiszpKrYNg8',
 *   status: 'COMPLETED',
 * });
 * @example <caption>a trackedEntityInstance</caption>
 * create('trackedEntityInstances', {
 *   orgUnit: 'TSyzvBiovKh',
 *   trackedEntityType: 'nEenWmSyUEp',
 *   attributes: [
 *     {
 *       attribute: 'w75KJ2mc4zz',
 *       value: 'Gigiwe',
 *     },
 *   ]
 * });
 * @example <caption>a dataSet</caption>
 * create('dataSets', { name: 'OpenFn Data Set', periodType: 'Monthly' });
 * @example <caption>a dataSetNotification</caption>
 * create('dataSetNotificationTemplates', {
 *   dataSetNotificationTrigger: 'DATA_SET_COMPLETION',
 *   notificationRecipient: 'ORGANISATION_UNIT_CONTACT',
 *   name: 'Notification',
 *   messageTemplate: 'Hello',
 *   deliveryChannels: ['SMS'],
 *   dataSets: [],
 * });
 * @example <caption>a dataElement</caption>
 * create('dataElements', {
 *   aggregationType: 'SUM',
 *   domainType: 'AGGREGATE',
 *   valueType: 'NUMBER',
 *   name: 'Paracetamol',
 *   shortName: 'Para',
 * });
 * @example <caption>a dataElementGroup</caption>
 * create('dataElementGroups', {
 *   name: 'Data Element Group 1',
 *   dataElements: [],
 * });
 * @example <caption>a dataElementGroupSet</caption>
 * create('dataElementGroupSets', {
 *   name: 'Data Element Group Set 4',
 *   dataDimension: true,
 *   shortName: 'DEGS4',
 *   dataElementGroups: [],
 * });
 * @example <caption>a dataValueSet</caption>
 * create('dataValueSets', {
 *   dataElement: 'f7n9E0hX8qk',
 *   period: '201401',
 *   orgUnit: 'DiszpKrYNg8',
 *   value: '12',
 * });
 * @example <caption>a dataValueSet with related dataValues</caption>
 * create('dataValueSets', {
 *   dataSet: 'pBOMPrpg1QX',
 *   completeDate: '2014-02-03',
 *   period: '201401',
 *   orgUnit: 'DiszpKrYNg8',
 *   dataValues: [
 *     {
 *       dataElement: 'f7n9E0hX8qk',
 *       value: '1',
 *     },
 *     {
 *       dataElement: 'Ix2HsbDMLea',
 *       value: '2',
 *     },
 *     {
 *       dataElement: 'eY5ehpbEsB7',
 *       value: '3',
 *     },
 *   ],
 * });
 * @example <caption>an enrollment</caption>
 * create('enrollments', {
 *   trackedEntityInstance: 'bmshzEacgxa',
 *   orgUnit: 'TSyzvBiovKh',
 *   program: 'gZBxv9Ujxg0',
 *   enrollmentDate: '2013-09-17',
 *   incidentDate: '2013-09-17',
 * });
 */
export function create(
  resourceType: string,
  data: Dhis2Data,
  options?: any,
  callback?: Function
): Operation;
/**
 * Update data. A generic helper function to update a resource object of any type.
 * Updating an object requires to send \`all required fields\` or the \`full body\`
 * @public
 * @function
 * @param {string} resourceType - The type of resource to be updated. E.g. \`dataElements\`, \`organisationUnits\`, etc.
 * @param {string} path - The \`id\` or \`path\` to the \`object\` to be updated. E.g. \`FTRrcoaog83\` or \`FTRrcoaog83/{collection-name}/{object-id}\`
 * @param {Object} data - Data to update. It requires to send \`all required fields\` or the \`full body\`. If you want \`partial updates\`, use \`patch\` operation.
 * @param {Object} [options] - Optional \`options\` to define URL parameters via params (E.g. \`filter\`, \`dimension\` and other import parameters), request config (E.g. \`auth\`) and the DHIS2 apiVersion.
 * @param {function} [callback]  - Optional callback to handle the response
 * @returns {Operation}
 * @example <caption>a program</caption>
 * update('programs', 'qAZJCrNJK8H', {
 *   name: '14e1aa02c3f0a31618e096f2c6d03bed',
 *   shortName: '14e1aa02',
 *   programType: 'WITHOUT_REGISTRATION',
 * });
 * @example <caption>an event</caption>
 * update('events', 'PVqUD2hvU4E', {
 *   program: 'eBAyeGv0exc',
 *   orgUnit: 'Ngelehun CHC',
 *   status: 'COMPLETED',
 *   storedBy: 'admin',
 *   dataValues: [],
 * });
 * @example <caption>a trackedEntityInstance</caption>
 * update('trackedEntityInstances', 'IeQfgUtGPq2', {
 *   created: '2015-08-06T21:12:37.256',
 *   orgUnit: 'TSyzvBiovKh',
 *   createdAtClient: '2015-08-06T21:12:37.256',
 *   trackedEntityInstance: 'IeQfgUtGPq2',
 *   lastUpdated: '2015-08-06T21:12:37.257',
 *   trackedEntityType: 'nEenWmSyUEp',
 *   inactive: false,
 *   deleted: false,
 *   featureType: 'NONE',
 *   programOwners: [
 *     {
 *       ownerOrgUnit: 'TSyzvBiovKh',
 *       program: 'IpHINAT79UW',
 *       trackedEntityInstance: 'IeQfgUtGPq2',
 *     },
 *   ],
 *   enrollments: [],
 *   relationships: [],
 *   attributes: [
 *     {
 *       lastUpdated: '2016-01-12T00:00:00.000',
 *       displayName: 'Last name',
 *       created: '2016-01-12T00:00:00.000',
 *       valueType: 'TEXT',
 *       attribute: 'zDhUuAYrxNC',
 *       value: 'Russell',
 *     },
 *     {
 *       lastUpdated: '2016-01-12T00:00:00.000',
 *       code: 'MMD_PER_NAM',
 *       displayName: 'First name',
 *       created: '2016-01-12T00:00:00.000',
 *       valueType: 'TEXT',
 *       attribute: 'w75KJ2mc4zz',
 *       value: 'Catherine',
 *     },
 *   ],
 * });
 * @example <caption>a dataSet</caption>
 * update('dataSets', 'lyLU2wR22tC', { name: 'OpenFN Data Set', periodType: 'Weekly' });
 * @example <caption>a dataSetNotification</caption>
 * update('dataSetNotificationTemplates', 'VbQBwdm1wVP', {
 *   dataSetNotificationTrigger: 'DATA_SET_COMPLETION',
 *   notificationRecipient: 'ORGANISATION_UNIT_CONTACT',
 *   name: 'Notification',
 *   messageTemplate: 'Hello Updated,
 *   deliveryChannels: ['SMS'],
 *   dataSets: [],
 * });
 * @example <caption>a dataElement</caption>
 * update('dataElements', 'FTRrcoaog83', {
 *   aggregationType: 'SUM',
 *   domainType: 'AGGREGATE',
 *   valueType: 'NUMBER',
 *   name: 'Paracetamol',
 *   shortName: 'Para',
 * });
 * @example <caption>a dataElementGroup</caption>
 * update('dataElementGroups', 'QrprHT61XFk', {
 *   name: 'Data Element Group 1',
 *   dataElements: [],
 * });
 * @example <caption>a dataElementGroupSet</caption>
 * update('dataElementGroupSets', 'VxWloRvAze8', {
 *   name: 'Data Element Group Set 4',
 *   dataDimension: true,
 *   shortName: 'DEGS4',
 *   dataElementGroups: [],
 * });
 * @example <caption>a dataValueSet</caption>
 * update('dataValueSets', 'AsQj6cDsUq4', {
 *   dataElement: 'f7n9E0hX8qk',
 *   period: '201401',
 *   orgUnit: 'DiszpKrYNg8',
 *   value: '12',
 * });
 * @example <caption>a dataValueSet with related dataValues</caption>
 * update('dataValueSets', 'Ix2HsbDMLea', {
 *   dataSet: 'pBOMPrpg1QX',
 *   completeDate: '2014-02-03',
 *   period: '201401',
 *   orgUnit: 'DiszpKrYNg8',
 *   dataValues: [
 *     {
 *       dataElement: 'f7n9E0hX8qk',
 *       value: '1',
 *     },
 *     {
 *       dataElement: 'Ix2HsbDMLea',
 *       value: '2',
 *     },
 *     {
 *       dataElement: 'eY5ehpbEsB7',
 *       value: '3',
 *     },
 *   ],
 * });
 * @example <caption>a single enrollment</caption>
 * update('enrollments', 'CmsHzercTBa' {
 *   trackedEntityInstance: 'bmshzEacgxa',
 *   orgUnit: 'TSyzvBiovKh',
 *   program: 'gZBxv9Ujxg0',
 *   enrollmentDate: '2013-10-17',
 *   incidentDate: '2013-10-17',
 * });
 */
export function update(
  resourceType: string,
  path: string,
  data: any,
  options?: any,
  callback?: Function
): Operation;
/**
 * Get data. Generic helper method for getting data of any kind from DHIS2.
 * - This can be used to get \`DataValueSets\`,\`events\`,\`trackedEntityInstances\`,\`etc.\`
 * @public
 * @function
 * @param {string} resourceType - The type of resource to get(use its \`plural\` name). E.g. \`dataElements\`, \`trackedEntityInstances\`,\`organisationUnits\`, etc.
 * @param {Object} query - A query object that will limit what resources are retrieved when converted into request params.
 * @param {Object} [options] - Optional \`options\` to define URL parameters via params beyond filters, request configuration (e.g. \`auth\`) and DHIS2 api version to use.
 * @param {function} [callback]  - Optional callback to handle the response
 * @returns {Operation} state
 * @example <caption>all data values for the 'pBOMPrpg1QX' dataset</caption>
 * get('dataValueSets', {
 *   dataSet: 'pBOMPrpg1QX',
 *   orgUnit: 'DiszpKrYNg8',
 *   period: '201401',
 *   fields: '*',
 * });
 * @example <caption>all programs for an organization unit</caption>
 * get('programs', { orgUnit: 'TSyzvBiovKh', fields: '*' });
 * @example <caption>a single tracked entity instance by a unique external ID</caption>
 * get('trackedEntityInstances', {
 *   ou: 'DiszpKrYNg8',
 *   filter: ['flGbXLXCrEo:Eq:124', 'w75KJ2mc4zz:Eq:John'],
 * });
 */
export function get(
  resourceType: string,
  query: any,
  options?: any,
  callback?: Function
): Operation;
/**
 * Upsert a record. A generic helper function used to atomically either insert a row, or on the basis of the row already existing, UPDATE that existing row instead.
 * @public
 * @function
 * @param {string} resourceType - The type of a resource to \`upsert\`. E.g. \`trackedEntityInstances\`
 * @param {Object} query - A query object that allows to uniquely identify the resource to update. If no matches found, then the resource will be created.
 * @param {Object} data - The data to use for update or create depending on the result of the query.
 * @param {{ apiVersion: object, requestConfig: object, params: object }} [options] - Optional configuration that will be applied to both the \`get\` and the \`create\` or \`update\` operations.
 * @param {function} [callback] - Optional callback to handle the response
 * @throws {RangeError} - Throws range error
 * @returns {Operation}
 * @example <caption>Example \`expression.js\` of upsert</caption>
 * upsert('trackedEntityInstances', {
 *  ou: 'TSyzvBiovKh',
 *  filter: ['w75KJ2mc4zz:Eq:Qassim'],
 * }, {
 *  orgUnit: 'TSyzvBiovKh',
 *  trackedEntityType: 'nEenWmSyUEp',
 *  attributes: [
 *    {
 *      attribute: 'w75KJ2mc4zz',
 *      value: 'Qassim',
 *    },
 *  ],
 * });
 */
export function upsert(
  resourceType: string,
  query: any,
  data: any,
  options?: {
    apiVersion: object;
    requestConfig: object;
    params: object;
  },
  callback?: Function
): Operation;
/**
 * Discover \`DHIS2\` \`api\` \`endpoint\` \`query parameters\` and allowed \`operators\` for a given resource's endpoint.
 * @public
 * @function
 * @param {string} httpMethod - The HTTP to inspect parameter usage for a given endpoint, e.g., \`get\`, \`post\`,\`put\`,\`patch\`,\`delete\`
 * @param {string} endpoint - The path for a given endpoint. E.g. \`/trackedEntityInstances\` or \`/dataValueSets\`
 * @returns {Operation}
 * @example <caption>a list of parameters allowed on a given endpoint for specific http method</caption>
 * discover('post', '/trackedEntityInstances')
 */
export function discover(httpMethod: string, endpoint: string): Operation;
/**
 * Patch a record. A generic helper function to send partial updates on one or more object properties.
 * - You are not required to send the full body of object properties.
 * - This is useful for cases where you don't want or need to update all properties on a object.
 * @public
 * @function
 * @param {string} resourceType - The type of resource to be updated. E.g. \`dataElements\`, \`organisationUnits\`, etc.
 * @param {string} path - The \`id\` or \`path\` to the \`object\` to be updated. E.g. \`FTRrcoaog83\` or \`FTRrcoaog83/{collection-name}/{object-id}\`
 * @param {Object} data - Data to update. Include only the fields you want to update. E.g. \`{name: "New Name"}\`
 * @param {Object} [options] - Optional configuration, including params for the update ({preheatCache: true, strategy: 'UPDATE', mergeMode: 'REPLACE'}). Defaults to \`{operationName: 'patch', apiVersion: state.configuration.apiVersion, responseType: 'json'}\`
 * @param {function} [callback] - Optional callback to handle the response
 * @returns {Operation}
 * @example <caption>a dataElement</caption>
 * patch('dataElements', 'FTRrcoaog83', { name: 'New Name' });
 */
export function patch(
  resourceType: string,
  path: string,
  data: any,
  options?: any,
  callback?: Function
): Operation;
/**
 * Delete a record. A generic helper function to delete an object
 * @public
 * @function
 * @param {string} resourceType - The type of resource to be deleted. E.g. \`trackedEntityInstances\`, \`organisationUnits\`, etc.
 * @param {string} path - Can be an \`id\` of an \`object\` or \`path\` to the \`nested object\` to \`delete\`.
 * @param {Object} [data] - Optional. This is useful when you want to remove multiple objects from a collection in one request. You can send \`data\` as, for example, \`{"identifiableObjects": [{"id": "IDA"}, {"id": "IDB"}, {"id": "IDC"}]}\`. See more {@link https://docs.dhis2.org/2.34/en/dhis2_developer_manual/web-api.html#deleting-objects on DHIS2 API docs}
 * @param {{apiVersion: number,operationName: string,resourceType: string}} [options] - Optional \`options\` for \`del\` operation including params e.g. \`{preheatCache: true, strategy: 'UPDATE', mergeMode: 'REPLACE'}\`. Run \`discover\` or see {@link https://docs.dhis2.org/2.34/en/dhis2_developer_manual/web-api.html#create-update-parameters DHIS2 documentation}. Defaults to \`{operationName: 'delete', apiVersion: state.configuration.apiVersion, responseType: 'json'}\`
 * @param {function} [callback] - Optional callback to handle the response
 * @returns {Operation}
 * @example <caption>a tracked entity instance</caption>
 * destroy('trackedEntityInstances', 'LcRd6Nyaq7T');
 */
export function destroy(
  resourceType: string,
  path: string,
  data?: any,
  options?: {
    apiVersion: number;
    operationName: string;
    resourceType: string;
  },
  callback?: Function
): Operation;
/**
 * Gets an attribute value by its case-insensitive display name
 * @public
 * @example
 * findAttributeValue(state.data.trackedEntityInstances[0], 'first name')
 * @function
 * @param {Object} trackedEntityInstance - A tracked entity instance (TEI) object
 * @param {string} attributeDisplayName - The 'displayName' to search for in the TEI's attributes
 * @returns {string}
 */
export function findAttributeValue(
  trackedEntityInstance: any,
  attributeDisplayName: string
): string;
/**
 * Converts an attribute ID and value into a DSHI2 attribute object
 * @public
 * @example
 * attr('w75KJ2mc4zz', 'Elias')
 * @function
 * @param {string} attribute - A tracked entity instance (TEI) attribute ID.
 * @param {string} value - The value for that attribute.
 * @returns {object}
 */
export function attr(attribute: string, value: string): object;
/**
 * Converts a dataElement and value into a DSHI2 dataValue object
 * @public
 * @example
 * dv('f7n9E0hX8qk', 12)
 * @function
 * @param {string} dataElement - A data element ID.
 * @param {string} value - The value for that data element.
 * @returns {object}
 */
export function dv(dataElement: string, value: string): object;
export {
  alterState,
  dataPath,
  dataValue,
  dateFns,
  each,
  field,
  fields,
  fn,
  http,
  lastReferenceValue,
  merge,
  sourceValue,
} from '@openfn/language-common';
`;
