import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { EstimateDocumentContent, type PortalEstimate } from "../app/EstimatePortal";

const fixture: PortalEstimate = {
  estimate: {
    id: "estimate", number: "EST-100", title: "Carpet replacement", status: "Draft",
    issued_at: "2026-10-21", subtotal: 2014.96, markup_percent: 0,
    markup_amount: 0, total: 2014.96, exclusions: [], payment_terms: "Due on completion",
    work_plan: [{ id: "prepare", title: "Prepare for work", steps: ["Protect adjacent surfaces."] }],
    notes: "Confirm access before starting.", appearance: { accent: "green", businessName: "Northside Builders" },
  },
  project: { id: "project", number: "PRJ-100", title: "Carpet replacement", address: "" },
  client: { name: "Taylor", company: "" }, business: { name: "Original business" },
  share: { status: "sent", expires_at: "2026-11-21" },
};

test("renders the PDF hierarchy and saved business name", () => {
  const html = renderToStaticMarkup(<EstimateDocumentContent estimate={fixture} token="" />);
  assert.match(html, /Northside Builders/);
  assert.doesNotMatch(html, /Original business/);
  assert.match(html, /\$2,014\.96/);
  assert.match(html, /Project plan/);
  assert.match(html, /Prepare for work/);
  assert.match(html, /Protect adjacent surfaces/);
  assert.match(html, /Confirm access before starting/);
  assert.match(html, /Payment terms/);
  assert.doesNotMatch(html, /Secure estimate|Estimate summary|status-pill/);
});

test("legacy estimates use the business name and safely escape text", () => {
  const legacy = { ...fixture, estimate: { ...fixture.estimate, appearance: undefined }, business: { name: "<script>unsafe</script>" } };
  const html = renderToStaticMarkup(<EstimateDocumentContent estimate={legacy} token="" />);
  assert.match(html, /&lt;script&gt;unsafe&lt;\/script&gt;/);
  assert.doesNotMatch(html, /<script>unsafe/);
});
