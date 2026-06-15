"use strict";

/**
 * Analytics normalization utilities for n8n Code nodes and standalone Node usage.
 *
 * Instagram timezone correction formula:
 * h_local = (h_api + delta_t_local) mod 24
 */

const PDT_UTC_OFFSET_HOURS = -7;

function mod(n, m) {
  return ((n % m) + m) % m;
}

function getLocalUtcOffsetHours(date = new Date()) {
  return -date.getTimezoneOffset() / 60;
}

function normalizeInstagramActiveHours(onlineFollowers, options = {}) {
  if (!Array.isArray(onlineFollowers) || onlineFollowers.length !== 24) {
    throw new Error("onlineFollowers must be an array of exactly 24 hour buckets.");
  }

  const apiUtcOffsetHours = Number.isFinite(options.apiUtcOffsetHours)
    ? options.apiUtcOffsetHours
    : PDT_UTC_OFFSET_HOURS;

  const localUtcOffsetHours = Number.isFinite(options.localUtcOffsetHours)
    ? options.localUtcOffsetHours
    : getLocalUtcOffsetHours();

  const deltaTLocal = localUtcOffsetHours - apiUtcOffsetHours;
  const roundedDelta = Math.round(deltaTLocal);

  if (Math.abs(deltaTLocal - roundedDelta) > 0.001) {
    throw new Error(
      "Non-integer timezone delta detected. Provide a normalized integer offset in hours for hour-bucket rotation."
    );
  }

  const shifted = new Array(24).fill(0);

  for (let hApi = 0; hApi < 24; hApi += 1) {
    const hLocal = mod(hApi + roundedDelta, 24);
    shifted[hLocal] = Number(onlineFollowers[hApi] || 0);
  }

  return {
    apiUtcOffsetHours,
    localUtcOffsetHours,
    deltaTLocalHours: roundedDelta,
    correctedHours: shifted,
  };
}

function extractMetricValue(metric) {
  if (!metric) return 0;
  if (typeof metric === "number") return metric;
  if (typeof metric.value === "number") return metric.value;
  if (Array.isArray(metric.values) && metric.values.length > 0) {
    return Number(metric.values[0].value || 0);
  }
  return 0;
}

function calculatePinterestOrganicCtr(analyticsResponse) {
  const data = analyticsResponse?.data || analyticsResponse;

  const impressions = extractMetricValue(
    data?.metrics?.impression || data?.metrics?.impressions || data?.impressions
  );
  const outboundClicks = extractMetricValue(
    data?.metrics?.outbound_click ||
      data?.metrics?.outbound_clicks ||
      data?.outbound_clicks
  );

  const ctr = impressions > 0 ? (outboundClicks / impressions) * 100 : 0;

  return {
    windowDays: 90,
    from_claimed_content: "CLAIMED",
    impressions,
    outboundClicks,
    ctr,
    ctrRounded2: Number(ctr.toFixed(2)),
  };
}

function buildPinterestOrganicAnalyticsRequestParams({ endDate = new Date() } = {}) {
  const to = new Date(endDate);
  const from = new Date(to);
  from.setDate(from.getDate() - 90);

  const formatDate = (d) => d.toISOString().slice(0, 10);

  return {
    start_date: formatDate(from),
    end_date: formatDate(to),
    from_claimed_content: "CLAIMED",
    metric_types: ["IMPRESSION", "OUTBOUND_CLICK"],
    split_field: "NO_SPLIT",
  };
}

function runInN8nCodeNode(items) {
  return items.map((item) => {
    const source = item.json || {};

    const ig = normalizeInstagramActiveHours(source.online_followers || source.onlineFollowers || [], {
      localUtcOffsetHours: Number.isFinite(source.localUtcOffsetHours)
        ? source.localUtcOffsetHours
        : getLocalUtcOffsetHours(),
      apiUtcOffsetHours: Number.isFinite(source.apiUtcOffsetHours)
        ? source.apiUtcOffsetHours
        : PDT_UTC_OFFSET_HOURS,
    });

    const pinterest = calculatePinterestOrganicCtr(source.pinterestAnalytics || source.pinterest || {});

    return {
      json: {
        ...source,
        instagramNormalization: ig,
        pinterestNormalization: pinterest,
      },
    };
  });
}

module.exports = {
  PDT_UTC_OFFSET_HOURS,
  getLocalUtcOffsetHours,
  normalizeInstagramActiveHours,
  calculatePinterestOrganicCtr,
  buildPinterestOrganicAnalyticsRequestParams,
  runInN8nCodeNode,
};

if (require.main === module) {
  const sample = {
    onlineFollowers: Array.from({ length: 24 }, (_, i) => i * 10),
    localUtcOffsetHours: -4,
    pinterestAnalytics: {
      metrics: {
        impressions: { value: 12000 },
        outbound_clicks: { value: 540 },
      },
    },
  };

  const output = runInN8nCodeNode([{ json: sample }]);
  // eslint-disable-next-line no-console
  console.log(JSON.stringify(output[0].json, null, 2));
}