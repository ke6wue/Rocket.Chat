import { db } from "./db.js";

// Importing db.js already runs CREATE TABLE IF NOT EXISTS for the full schema.
console.log(`Schema ready at ${db.name}`);
db.close();
