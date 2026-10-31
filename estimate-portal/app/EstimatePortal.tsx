"use client";

import { useEffect, useState, type CSSProperties } from "react";

const SUPABASE_URL = "https://tuykoxmpnmrawrknjikr.supabase.co";
const SUPABASE_KEY = "sb_publishable_mYhHJdb0mfCTvUWdGAWrpg_jmbY9GV-";
const SHARE_TOKEN_PATTERN = /^[a-f0-9]{64}$/;
const MAX_SIGNER_LENGTH = 120;
const MAX_CHANGE_REQUEST_LENGTH = 4_000;

type WorkPlanSection = {
  id: string;
  title: string;
  steps: string[];
};

type EstimateMedia = {
  id: string;
  kind: "photo" | "floorplan" | "render";
  display_name: string;
};

export type PortalEstimate = {
  estimate: {
    id: string;
    number: string;
    title: string;
    status: string;
    issued_at: string;
    subtotal: number;
    markup_percent: number;
    markup_amount: number;
    contingency_amount?: number;
    total: number;
    appearance?: { accent?: string; businessName?: string };
    work_plan?: WorkPlanSection[];
    notes?: string;
    exclusions: string[];
    payment_terms: string;
  };
  project: {
    id: string;
    number: string;
    title: string;
    address: string;
  };
  client: {
    name: string;
    company: string;
  };
  business: {
    name: string;
  };
  media?: EstimateMedia[];
  share: {
    status: string;
    expires_at: string;
    approved_at?: string;
    approved_by?: string;
    change_request?: string;
  };
};

function PortalMedia({ token, media }: { token: string; media: EstimateMedia }) {
  const [source, setSource] = useState<string | null>(null);
  const [contentType, setContentType] = useState("");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const controller = new AbortController();
    let objectURL = "";

    fetch(`${SUPABASE_URL}/functions/v1/estimate-media`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token, media_id: media.id }),
      cache: "no-store",
      credentials: "omit",
      referrerPolicy: "no-referrer",
      signal: controller.signal,
    })
      .then(async (response) => {
        if (!response.ok) throw new Error("Media unavailable");
        setContentType(response.headers.get("content-type") || "");
        objectURL = URL.createObjectURL(await response.blob());
        setSource(objectURL);
      })
      .catch((requestError) => {
        if (requestError instanceof DOMException && requestError.name === "AbortError") return;
        setFailed(true);
      });

    return () => {
      controller.abort();
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [media.id, token]);

  const label = media.kind === "floorplan" ? "Floor plan" : media.kind === "render" ? "Render" : "Photo";

  return (
    <figure className="media-card">
      <div className="media-preview">
        {!source && !failed && <span className="media-loading">Loading {label.toLowerCase()}…</span>}
        {failed && <span className="media-loading">{label} unavailable</span>}
        {source && contentType.includes("pdf") && (
          <object data={source} type="application/pdf" aria-label={media.display_name}>
            <a href={source}>Open {media.display_name}</a>
          </object>
        )}
        {source && !contentType.includes("pdf") && (
          // The URL is a local blob created from the authenticated POST response.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={source} alt={media.display_name} />
        )}
      </div>
      <figcaption>
        <span>{label}</span>
        <strong>{media.display_name}</strong>
      </figcaption>
    </figure>
  );
}

const accents: Record<string, string> = {
  blue: "#285C9B", black: "#202124", gray: "#60646C", green: "#287052",
};

const money = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
});

const date = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric",
});

async function rpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
  });

  if (!response.ok) {
    throw new Error("The secure request could not be completed. Please try again.");
  }

  return response.json();
}

function readShareToken(): string {
  if (typeof window === "undefined") return "";

  const url = new URL(window.location.href);
  const fragmentToken = new URLSearchParams(
    url.hash.startsWith("#") ? url.hash.slice(1) : url.hash,
  ).get("token");
  return fragmentToken || url.searchParams.get("token") || "";
}

export function EstimateDocumentContent({ estimate, token }: { estimate: PortalEstimate; token: string }) {
  const savedName = estimate.estimate.appearance?.businessName;
  const businessName = typeof savedName === "string" ? savedName.trim() : estimate.business.name;
  return <>
          <header className="estimate-head">
            {businessName && <p className="business-name">{businessName}</p>}
            <p className="eyebrow">Estimate</p>
            <h1>{estimate.estimate.title}</h1>
            <p className="estimate-number">{estimate.estimate.number}</p>
            {estimate.client.name !== "Client" && (
              <div className="bill-to">
                <span>Bill to</span>
                <strong>{estimate.client.name}</strong>
                {estimate.client.company && <p>{estimate.client.company}</p>}
              </div>
            )}
          </header>
          <div className="estimate-body">
            <h2 className="section-title">Estimate total</h2>
            <section className="estimate-total-card" aria-label="Final estimate total">
              <span>Final estimate</span>
              <strong>{money.format(estimate.estimate.total)}</strong>
              <p>The project plan, notes, and supporting visuals are included below.</p>
            </section>

            {(estimate.estimate.work_plan?.length ?? 0) > 0 && (
              <section className="proposal-section" aria-labelledby="project-plan-heading">
                <h2 className="section-title" id="project-plan-heading">Project plan</h2>
                <div className="plan-grid">
                  {(estimate.estimate.work_plan ?? []).map((section, index) => (
                    <article className="plan-card" key={section.id}>
                      <div>
                        <h3>{index + 1}. &nbsp;{section.title}</h3>
                        <ul>
                          {section.steps.map((step, stepIndex) => (
                            <li key={`${section.id}-${stepIndex}`}>{step}</li>
                          ))}
                        </ul>
                      </div>
                    </article>
                  ))}
                </div>
              </section>
            )}

            {(estimate.media?.length ?? 0) > 0 && (
              <section className="proposal-section" aria-labelledby="estimate-media-heading">
                <h2 className="section-title" id="estimate-media-heading">Photos &amp; plans</h2>
                <div className="media-grid">
                  {(estimate.media ?? []).map((media) => (
                    <PortalMedia key={media.id} token={token} media={media} />
                  ))}
                </div>
              </section>
            )}

            {estimate.estimate.notes?.trim() && (
              <section className="proposal-section" aria-labelledby="estimate-notes-heading">
                <h2 className="section-title" id="estimate-notes-heading">Notes</h2>
                <div className="notes-card">{estimate.estimate.notes}</div>
              </section>
            )}

            {estimate.estimate.payment_terms && (
              <section className="terms">
                {estimate.estimate.payment_terms && (
                  <div>
                    <h2 className="section-title">Payment terms</h2>
                    <p>{estimate.estimate.payment_terms}</p>
                  </div>
                )}

              </section>
            )}
          </div>
  </>;
}

export function EstimatePortal() {
  const [token] = useState(readShareToken);
  const [estimate, setEstimate] = useState<PortalEstimate | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<"approve" | "change" | null>(null);
  const [signer, setSigner] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [changeMessage, setChangeMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const hasValidToken = SHARE_TOKEN_PATTERN.test(token);

  useEffect(() => {
    if (!SHARE_TOKEN_PATTERN.test(token)) return;

    const currentURL = new URL(window.location.href);
    if (currentURL.searchParams.has("token")) {
      currentURL.searchParams.delete("token");
      currentURL.hash = new URLSearchParams({ token }).toString();
      window.history.replaceState(null, "", currentURL);
    }

    rpc<PortalEstimate | null>("get_public_estimate", { p_token: token })
      .then((result) => {
        if (!result) {
          setError("This estimate link has expired or is no longer available.");
        } else {
          setEstimate(result);
          setSigner(result.client.name === "Client" ? "" : result.client.name);
        }
      })
      .catch((requestError) => setError(requestError.message))
      .finally(() => setLoading(false));
  }, [token]);

  const isApproved = estimate?.share.status === "approved";
  const changesRequested = estimate?.share.status === "changes_requested";

  async function approve() {
    if (!confirmed || !signer.trim()) return;
    setError(null);
    setSubmitting(true);
    try {
      const result = await rpc<{
        status: string;
        approved_by: string;
        approved_at: string;
      }>("approve_public_estimate", {
        p_token: token,
        p_approved_by: signer.trim(),
      });
      setEstimate((current) => current ? {
        ...current,
        share: {
          ...current.share,
          status: result.status,
          approved_by: result.approved_by,
          approved_at: result.approved_at,
        },
      } : current);
      setDialog(null);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Approval failed.");
    } finally {
      setSubmitting(false);
    }
  }

  async function requestChange() {
    if (!changeMessage.trim()) return;
    setError(null);
    setSubmitting(true);
    try {
      const result = await rpc<{ status: string; message: string }>(
        "request_public_estimate_change",
        {
          p_token: token,
          p_message: changeMessage.trim(),
        },
      );
      setEstimate((current) => current ? {
        ...current,
        share: {
          ...current.share,
          status: result.status,
          change_request: result.message,
        },
      } : current);
      setDialog(null);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Request failed.");
    } finally {
      setSubmitting(false);
    }
  }

  if (!hasValidToken) {
    return (
      <main className="portal">
        <section className="state-card">
          <div className="brand-mark" style={{ margin: "0 auto 18px" }}>E</div>
          <h1>Estimate unavailable</h1>
          <p>This estimate link is incomplete. Ask the contractor to send a new link.</p>
        </section>
      </main>
    );
  }

  if (loading) {
    return (
      <main className="portal">
        <section className="state-card" role="status">
          <div className="spinner" />
          <h1>Opening your estimate</h1>
          <p>Loading the latest secure copy.</p>
        </section>
      </main>
    );
  }

  if (!estimate) {
    return (
      <main className="portal">
        <section className="state-card">
          <div className="brand-mark" style={{ margin: "0 auto 18px" }}>E</div>
          <h1>Estimate unavailable</h1>
          <p>{error}</p>
        </section>
      </main>
    );
  }

  const actions = (
    <div className="actions">
      <button className="action-button" onClick={() => window.print()}>
        <span className="action-icon" aria-hidden="true">↓</span>
        <span>Download<span className="action-label-long"> PDF</span></span>
      </button>
      <button
        className="action-button"
        onClick={() => setDialog("change")}
        disabled={isApproved || changesRequested}
      >
        <span className="action-icon" aria-hidden="true">↗</span>
        <span>Request change</span>
      </button>
      <button
        className="action-button primary"
        onClick={() => setDialog("approve")}
        disabled={isApproved || changesRequested}
      >
        <span className="action-icon" aria-hidden="true">✓</span>
        <span>{isApproved ? "Approved" : "Approve"}</span>
      </button>
    </div>
  );

  const appearance = estimate.estimate.appearance;
  const accent = accents[appearance?.accent ?? "blue"] ?? accents.blue;

  return (
    <main className="portal" style={{ "--blue": accent, "--blue-light": accent } as CSSProperties}>
      <div className="shell">
        <div className="top-actions">{actions}</div>
        <article className="estimate-card">
          <EstimateDocumentContent estimate={estimate} token={token} />

          {isApproved && (
            <div className="approval-receipt">
              <strong>Estimate approved by {estimate.share.approved_by}</strong>
              <span>
                {estimate.share.approved_at
                  ? date.format(new Date(estimate.share.approved_at))
                  : "Approval recorded"}
              </span>
            </div>
          )}

          {changesRequested && (
            <div className="approval-receipt" style={{ color: "#7a5410", background: "#fff7df" }}>
              <strong>Changes requested</strong>
              <span>{estimate.share.change_request}</span>
            </div>
          )}
        </article>
      </div>

      <footer className="portal-footer">
        <a href="/privacy">Privacy Policy</a>
      </footer>

      {error && <p className="portal-error" role="alert">{error}</p>}
      <div className="bottom-actions">{actions}</div>

      {dialog && (
        <div className="modal-backdrop" role="presentation" onMouseDown={() => setDialog(null)}>
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="dialog-title"
            onMouseDown={(event) => event.stopPropagation()}
          >
            {error && <p role="alert">{error}</p>}
            {dialog === "approve" ? (
              <>
                <h2 id="dialog-title">Approve this estimate</h2>
                <p className="modal-copy">
                  Your approval will be recorded with your name, the estimate total,
                  and the time you approved it.
                </p>
                <label className="field-label" htmlFor="signer">Your full name</label>
                <input
                  id="signer"
                  className="field"
                  value={signer}
                  onChange={(event) => setSigner(event.target.value)}
                  autoComplete="name"
                  maxLength={MAX_SIGNER_LENGTH}
                />
                <label className="checkbox-row">
                  <input
                    type="checkbox"
                    checked={confirmed}
                    onChange={(event) => setConfirmed(event.target.checked)}
                  />
                  <span>
                    I approve estimate {estimate.estimate.number} for{" "}
                    {money.format(estimate.estimate.total)} and authorize the contractor
                    to proceed with the described work.
                  </span>
                </label>
                <div className="modal-actions">
                  <button className="action-button" onClick={() => setDialog(null)}>Cancel</button>
                  <button
                    className="action-button primary"
                    onClick={approve}
                    disabled={!confirmed || !signer.trim() || submitting}
                  >
                    {submitting ? "Approving…" : "Confirm approval"}
                  </button>
                </div>
              </>
            ) : (
              <>
                <h2 id="dialog-title">Request a change</h2>
                <p className="modal-copy">
                  Tell the contractor what you would like adjusted. They’ll receive
                  your note with this estimate.
                </p>
                <label className="field-label" htmlFor="change-message">Requested change</label>
                <textarea
                  id="change-message"
                  className="field"
                  value={changeMessage}
                  onChange={(event) => setChangeMessage(event.target.value)}
                  placeholder="Example: Please remove the optional fixture upgrade."
                  maxLength={MAX_CHANGE_REQUEST_LENGTH}
                  autoFocus
                />
                <div className="modal-actions">
                  <button className="action-button" onClick={() => setDialog(null)}>Cancel</button>
                  <button
                    className="action-button primary"
                    onClick={requestChange}
                    disabled={!changeMessage.trim() || submitting}
                  >
                    {submitting ? "Sending…" : "Send request"}
                  </button>
                </div>
              </>
            )}
          </section>
        </div>
      )}
    </main>
  );
}
