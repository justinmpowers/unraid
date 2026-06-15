"use strict";

const fs = require("fs");
const path = require("path");
const axios = require("axios");
const FormData = require("form-data");

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function buildClient() {
  const token = requiredEnv("ETSY_ACCESS_TOKEN");
  const apiKey = requiredEnv("ETSY_CLIENT_ID");

  return axios.create({
    baseURL: process.env.ETSY_API_BASE_URL || "https://openapi.etsy.com",
    timeout: 30000,
    headers: {
      Authorization: `Bearer ${token}`,
      "x-api-key": apiKey,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
  });
}

function buildDraftPayload(input = {}) {
  return {
    quantity: Number(input.quantity || process.env.ETSY_LISTING_QUANTITY || 1),
    title: String(input.title || process.env.ETSY_LISTING_TITLE || "Draft Listing Title"),
    description: String(
      input.description ||
        process.env.ETSY_LISTING_DESCRIPTION ||
        "Draft listing created programmatically for approval."
    ),
    price: Number(input.price || process.env.ETSY_LISTING_PRICE || 10.0),
    who_made: String(input.who_made || process.env.ETSY_WHO_MADE || "i_did"),
    when_made: String(input.when_made || process.env.ETSY_WHEN_MADE || "made_to_order"),
    taxonomy_id: Number(input.taxonomy_id || process.env.ETSY_TAXONOMY_ID || 1429),
    shipping_profile_id: Number(
      input.shipping_profile_id || process.env.ETSY_SHIPPING_PROFILE_ID
    ),
    state: "draft",
  };
}

function validateDraftPayload(payload) {
  const requiredFields = [
    "quantity",
    "title",
    "description",
    "price",
    "who_made",
    "when_made",
    "taxonomy_id",
    "shipping_profile_id",
  ];

  const missing = requiredFields.filter((key) => {
    const value = payload[key];
    return value === undefined || value === null || value === "";
  });

  if (missing.length > 0) {
    throw new Error(`Draft payload is missing required fields: ${missing.join(", ")}`);
  }
}

async function createDraftListing(client, shopId, payload) {
  const endpoint = `/v3/application/shops/${shopId}/listings`;
  const response = await client.post(endpoint, payload);
  return response.data;
}

async function uploadListingImage(client, shopId, listingId, imagePath) {
  if (!imagePath) {
    throw new Error("ETSY_LISTING_IMAGE_PATH is required for draft image upload.");
  }

  const resolvedPath = path.resolve(imagePath);
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`Listing image file does not exist: ${resolvedPath}`);
  }

  const form = new FormData();
  form.append("image", fs.createReadStream(resolvedPath));
  form.append("rank", "1");

  const endpoint = `/v3/application/shops/${shopId}/listings/${listingId}/images`;
  const response = await client.post(endpoint, form, {
    headers: {
      ...form.getHeaders(),
      Authorization: client.defaults.headers.Authorization,
      "x-api-key": client.defaults.headers["x-api-key"],
    },
    maxBodyLength: Infinity,
  });

  return response.data;
}

async function activateListing(client, shopId, listingId) {
  const endpoint = `/v3/application/shops/${shopId}/listings/${listingId}`;
  const response = await client.patch(endpoint, { state: "active" });
  return response.data;
}

function formatAxiosError(error) {
  if (error.response) {
    return {
      status: error.response.status,
      statusText: error.response.statusText,
      data: error.response.data,
      headers: error.response.headers,
    };
  }

  return {
    message: error.message,
  };
}

async function main() {
  const shopId = requiredEnv("ETSY_SHOP_ID");
  const imagePath = process.env.ETSY_LISTING_IMAGE_PATH;
  const dryRun = String(process.env.DRY_RUN || "false").toLowerCase() === "true";

  const client = buildClient();
  const payload = buildDraftPayload();
  validateDraftPayload(payload);

  if (dryRun) {
    console.log("[DRY_RUN] Listing payload validated. No API calls executed.");
    console.log(JSON.stringify(payload, null, 2));
    return;
  }

  try {
    console.log("Creating Etsy draft listing...");
    const draft = await createDraftListing(client, shopId, payload);

    const listingId = draft.listing_id || draft.listingId;
    if (!listingId) {
      throw new Error("Etsy response did not include listing_id.");
    }

    console.log(`Draft created. listing_id=${listingId}`);

    console.log("Uploading listing image before activation...");
    const imageUpload = await uploadListingImage(client, shopId, listingId, imagePath);
    console.log("Image upload complete.");

    console.log("Activating listing after successful image upload...");
    const activated = await activateListing(client, shopId, listingId);
    console.log("Listing activated successfully.");

    console.log(
      JSON.stringify(
        {
          draft,
          imageUpload,
          activated,
        },
        null,
        2
      )
    );
  } catch (error) {
    console.error("Etsy draft creation flow failed.");
    console.error(JSON.stringify(formatAxiosError(error), null, 2));
    process.exitCode = 1;
  }
}

module.exports = {
  buildClient,
  buildDraftPayload,
  validateDraftPayload,
  createDraftListing,
  uploadListingImage,
  activateListing,
};

if (require.main === module) {
  main();
}