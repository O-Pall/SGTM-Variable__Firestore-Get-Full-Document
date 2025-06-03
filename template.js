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
