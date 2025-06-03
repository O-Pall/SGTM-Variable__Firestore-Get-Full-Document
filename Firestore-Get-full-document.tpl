___INFO___

{
  "type": "MACRO",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "Firestore - Get full document",
  "description": "",
  "containerContexts": [
    "SERVER"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "LABEL",
    "name": "note",
    "displayName": "Always returns a \u003cstrong\u003efull\u003c/strong\u003e document.\u003cbr\u003e\u003cbr\u003e\n\n\u003cstrong\u003eDocument queries\u003c/strong\u003e\u003cbr\u003e\n\nReturns a \u003cstrong\u003esingle\u003c/strong\u003e document based on its document id. \u003cbr\u003e\u003cbr\u003e \n\n\n\u003cstrong\u003eField queries\u003c/strong\u003e\u003cbr\u003e\nPass \u003cstrong\u003eone\u003c/strong\u003e or \u003cstrong\u003emultiple\u003c/strong\u003e values resolving to a specific \u003cstrong\u003efield\u003c/strong\u003e from your document.\u003cbr\u003e\nIf your input value contains duplicates, it is cleaned to only send unique requests to Firestore.\u003cbr\u003e\nRequests are batched to minimize requests done to Firestore.\u003cbr\u003e\u003cbr\u003e"
  },
  {
    "type": "TEXT",
    "name": "googleCloudProjectId",
    "displayName": "Google Cloud Project ID",
    "simpleValueType": true
  },
  {
    "type": "TEXT",
    "name": "collection",
    "displayName": "Collection",
    "simpleValueType": true,
    "help": "The name of the collection you want to \u003cstrong\u003equery\u003c/strong\u003e."
  },
  {
    "type": "RADIO",
    "name": "queryType",
    "displayName": "What do you want to query ?",
    "radioItems": [
      {
        "value": "document",
        "displayValue": "Document"
      },
      {
        "value": "field",
        "displayValue": "Field"
      }
    ],
    "simpleValueType": true
  },
  {
    "type": "GROUP",
    "name": "groupDocument",
    "groupStyle": "NO_ZIPPY",
    "subParams": [
      {
        "type": "TEXT",
        "name": "documentId",
        "displayName": "Document ID",
        "simpleValueType": true
      }
    ],
    "enablingConditions": [
      {
        "paramName": "queryType",
        "paramValue": "document",
        "type": "EQUALS"
      }
    ]
  },
  {
    "type": "GROUP",
    "name": "groupField",
    "groupStyle": "NO_ZIPPY",
    "subParams": [
      {
        "type": "TEXT",
        "name": "fieldName",
        "displayName": "Field name",
        "simpleValueType": true
      },
      {
        "type": "TEXT",
        "name": "fieldValue",
        "displayName": "Value(s) to find",
        "simpleValueType": true
      },
      {
        "type": "TEXT",
        "name": "delimiter",
        "displayName": "Delimiter",
        "simpleValueType": true,
        "help": ""
      }
    ],
    "enablingConditions": [
      {
        "paramName": "queryType",
        "paramValue": "field",
        "type": "EQUALS"
      }
    ]
  }
]


___SANDBOXED_JS_FOR_SERVER___

const Firestore = require('Firestore');
const log = require('logToConsole');

const projectId = data.googleCloudProjectId;
const collection = data.collection;
const queryType = data.queryType;
const firestoreOptions = { projectId: projectId };

// Validation des entrées obligatoires
if (!projectId || !collection) {
  log("Erreur: googleCloudProjectID et collection sont requis");
  return undefined;
}

/**
 * FONCTIONS UTILITAIRES
 */

// Lit un document par son ID
function readDocumentById(coll, docId) {
  log("Lecture du document: " + coll + "/" + docId);
  
  return Firestore.read(coll + '/' + docId, firestoreOptions)
    .then(function(document) {
log("Document trouvé: " + document.data);
      return document.data;
    })
    .catch(function() {
      log("Document non trouvé: " + docId);
      return undefined;
    });
}

// Requête un document par valeur de champ
function querySingleValueByField(coll, fieldName, value) {
  log("Requête par champ: " + fieldName + " = " + value);
  
  return Firestore.query(coll, [[fieldName, '==', value]], firestoreOptions)
    .then(function(documents) {
      if (!documents || documents.length === 0) {
        log("Aucun document trouvé pour " + fieldName + " = " + value);
        return undefined;
      }
      // Retourner un tableau avec le premier document
      return [documents[0].data];
    })
    .catch(function() {
      return undefined;
    });
}

// Requête multiple par valeur de champ (avec traitement par lots)
function queryMultipleValuesByField(coll, fieldName, values) {
  log("Requête multiple par " + fieldName + " avec " + values.length + " valeurs");
  
  // Diviser en lots de 10 (limite de Firestore pour l'opérateur 'in')
  const batches = createBatches(values, 10);
  
  // Traiter les lots séquentiellement avec un tableau vide comme accumulateur
  return processNextBatch(0, [], coll, fieldName, batches);
}

// Extrait les valeurs uniques d'une chaîne
function extractUniqueValues(value, delimiter) {
  if (!delimiter) {
    return [value]; // Pas de délimiteur, une seule valeur
  }
  
  const result = [];
  const seen = {};
  const parts = value.split(delimiter);
  
  for (let i = 0; i < parts.length; i++) {
    const val = parts[i].trim();
    if (val && !seen[val]) {
      seen[val] = true;
      result.push(val);
    }
  }
  
  return result;
}

// Crée des lots de taille spécifiée
function createBatches(items, batchSize) {
  const result = [];
  
  for (let i = 0; i < items.length; i += batchSize) {
    const batch = [];
    const end = (i + batchSize < items.length) ? i + batchSize : items.length;
    
    for (let j = i; j < end; j++) {
      batch.push(items[j]);
    }
    
    result.push(batch);
  }
  
  return result;
}

// Traite les lots séquentiellement
function processNextBatch(index, results, coll, fieldName, batches) {
  // Si tous les lots sont traités, retourner les résultats
  if (index >= batches.length) {
    // Vérifier si nous avons des résultats
    if (!results || results.length === 0) {
      return undefined;
    }
    return results;
  }
  
  // Construire la requête pour le lot courant
  const currentBatch = batches[index];
  
  // Exécuter la requête
  return Firestore.query(coll, [[fieldName, 'in', currentBatch]], firestoreOptions)
    .then(function(documents) {
      // Ajouter les résultats au tableau
      for (let i = 0; i < documents.length; i++) {
        const doc = documents[i];
        if (doc.data) {
          results.push(doc.data);
        }
      }
      
      // Traiter le lot suivant
      return processNextBatch(index + 1, results, coll, fieldName, batches);
    })
    .catch(function() {
      log("Erreur sur le lot " + (index + 1));
      return processNextBatch(index + 1, results, coll, fieldName, batches);
    });
}


/*
 * LOGIQUE PRINCIPALE
 */
if (queryType === 'document') {
    // CAS 1: Requête par ID de document
    const documentId = data.documentId;
    if (!documentId) {
      log("Erreur: documentId est requis pour les requêtes de type 'document'");
      return undefined;
    }
    
    return readDocumentById(collection, documentId);
}
  
if (queryType === 'field') {
    // CAS 2: Requête par champ
    const fieldName = data.fieldName;
    const fieldValue = data.fieldValue;
    const delimiter = data.delimiter;
    
    if (!fieldName || !fieldValue) {
      log("Erreur: fieldName et fieldValue sont requis pour les requêtes de type 'field'");
      return undefined;
    }
    
    // Extraire les valeurs uniques
    const values = extractUniqueValues(fieldValue, delimiter);
    if (values.length === 0) {
      log("Aucune valeur valide trouvée");
      return undefined;
    }
    
    if (values.length === 1) {
      // Une seule valeur, requête simple
      return querySingleValueByField(collection, fieldName, values[0]);
    } else {
      // Plusieurs valeurs, requête par lots
      return queryMultipleValuesByField(collection, fieldName, values);
    }
  }


___SERVER_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "logging",
        "versionId": "1"
      },
      "param": [
        {
          "key": "environments",
          "value": {
            "type": 1,
            "string": "all"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "access_firestore",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedOptions",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "projectId"
                  },
                  {
                    "type": 1,
                    "string": "path"
                  },
                  {
                    "type": 1,
                    "string": "operation"
                  },
                  {
                    "type": 1,
                    "string": "databaseId"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "*"
                  },
                  {
                    "type": 1,
                    "string": "*"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "(default)"
                  }
                ]
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios:
- name: Document - simple
  code: |2-
      // Setup
      const mockData = {
        googleCloudProjectId: "secteurs-maps-analytics",
        collection: "products",
        queryType: 'document',

        documentId: '05100-1406'
      };

      // Run test
      let variableResult = runCode(mockData);

      // Assert
      assertThat(variableResult).isObject();
- name: Field - simple
  code: "  // Setup\n  const mockData = {\n    googleCloudProjectId: \"secteurs-maps-analytics\"\
    ,\n    collection: \"products\",\n    queryType: 'field',\n    \n    fieldName:\
    \ 'item_id',\n    fieldValue: \"05100-1406\",\n    delimiter : \",\"\n  };\n\n\
    \  // Run test\n  let variableResult = runCode(mockData);\n\n  // Assert\n  assertThat(variableResult).isObject();\n\
    \n"
- name: Field - Multiple
  code: "  // Setup\n  const mockData = {\n    googleCloudProjectId: \"secteurs-maps-analytics\"\
    ,\n    collection: \"products\",\n    queryType: 'field',\n    \n    fieldName:\
    \ 'item_id',\n    fieldValue: \"05100-1406,00100-0637,00100-0638,00100-0639,00100-0640,00100-0641,00200-0721,00200-0758,00200-0759,00200-0760,00200-0761,00200-0762\"\
    ,\n    delimiter : \",\"\n  };\n\n  // Run test\n  let variableResult = runCode(mockData);\n\
    \n  // Assert\n  assertThat(variableResult).isObject();\n\n"


___NOTES___

Created on 03/06/2025 14:34:06


