import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of Use | EasyBid",
  description: "Terms governing use of the EasyBid app and client portal.",
  robots: { index: true, follow: true },
};

const effectiveDate = "July 31, 2026";

export default function TermsPage() {
  return (
    <main className="policy-page">
      <article className="policy-document">
        <header className="policy-header">
          <Link className="policy-brand" href="/" aria-label="EasyBid estimate portal">
            <span className="brand-mark">E</span>
            <span>EasyBid</span>
          </Link>
          <p className="eyebrow">Legal</p>
          <h1>Terms of Use</h1>
          <p className="policy-effective">Effective and last updated: {effectiveDate}</p>
          <p className="policy-intro">
            These Terms govern use of the EasyBid iOS app, client-review portal,
            and related services (the &quot;Service&quot;). By creating an
            account or using the Service, you agree to these Terms and the{" "}
            <Link href="/privacy">Privacy Policy</Link>.
          </p>
        </header>

        <section>
          <h2>1. Business use and account security</h2>
          <p>
            EasyBid is a tool for contractors and businesses. You must provide
            accurate account information, protect your sign-in credentials and
            client-review links, and promptly report suspected unauthorized use.
            You are responsible for activity performed through your account.
          </p>
        </section>

        <section>
          <h2>2. Your clients, projects, and content</h2>
          <p>
            You retain ownership of content you submit. You grant EasyBid a
            limited license to host, process, transmit, and display that content
            only as needed to operate, secure, and support the Service. You must
            have permission and a lawful basis to submit information about
            clients, workers, properties, photos, recordings, and projects.
          </p>
        </section>

        <section>
          <h2>3. AI-assisted features</h2>
          <p>
            When you affirmatively allow AI features and use AI Chat, your chat
            messages, relevant project information, and photos, video frames, or
            audio you intentionally attach are processed through OpenAI&apos;s API
            to provide the requested feature. You can withdraw AI permission in
            Privacy &amp; Permissions. AI output may be incomplete, inaccurate, or
            unsuitable for a particular job. You must review scope, quantities,
            codes, pricing, taxes, safety requirements, and contract terms before
            relying on or sending an AI-assisted estimate.
          </p>
        </section>

        <section>
          <h2>4. Estimates, invoices, and client approvals</h2>
          <p>
            EasyBid does not provide legal, tax, engineering, code-compliance, or
            financial advice and is not a party to agreements between contractors
            and their clients. You are responsible for your prices, work, permits,
            disclosures, taxes, payment terms, and compliance obligations. A
            portal approval records the recipient&apos;s action but does not replace
            any signature or contract formalities required by law.
          </p>
        </section>

        <section>
          <h2>5. Subscriptions</h2>
          <p>
            Paid subscriptions are billed and administered by Apple under the
            terms shown at purchase. To cancel, open iPhone Settings, tap your
            name, choose Subscriptions, select EasyBid, and tap Cancel
            Subscription. Deleting the app or your EasyBid account does not itself
            cancel an Apple subscription.
          </p>
        </section>

        <section>
          <h2>6. Acceptable use</h2>
          <p>You may not:</p>
          <ul>
            <li>access another person&apos;s account, project, or portal link without authorization;</li>
            <li>probe, bypass, or interfere with authentication, quotas, security controls, or availability;</li>
            <li>submit malware, unlawful content, or content that violates another person&apos;s rights;</li>
            <li>use automated means to scrape, overload, resell, or reverse engineer the Service except where law permits; or</li>
            <li>use the Service for deceptive, fraudulent, dangerous, or illegal activity.</li>
          </ul>
        </section>

        <section>
          <h2>7. Availability and changes</h2>
          <p>
            We may maintain, secure, update, limit, or discontinue features. We do
            not promise uninterrupted availability or permanent storage. Keep
            independent copies of important business records.
          </p>
        </section>

        <section>
          <h2>8. Suspension and termination</h2>
          <p>
            We may suspend or terminate access when reasonably necessary to
            protect users or the Service, investigate abuse, comply with law, or
            address a material violation. You may stop using EasyBid and may
            delete your account from the app, subject to the separate Apple
            subscription instructions above.
          </p>
        </section>

        <section>
          <h2>9. Disclaimers and responsibility</h2>
          <p>
            To the extent permitted by law, the Service is provided “as is” and
            “as available.” EasyBid disclaims implied warranties of
            merchantability, fitness for a particular purpose, and
            non-infringement. Nothing in these Terms excludes rights or liability
            that cannot lawfully be excluded.
          </p>
        </section>

        <section>
          <h2>10. Contact and updates</h2>
          <p>
            Questions may be submitted through the{" "}
            <Link href="/support">EasyBid Support page</Link>. We may update these
            Terms as the Service or law changes and will post the revised date.
          </p>
        </section>

        <footer className="policy-footer">
          <span>© {new Date().getFullYear()} EasyBid</span>
          <Link href="/">Estimate portal</Link>
          <Link href="/privacy">Privacy Policy</Link>
          <Link href="/support">Support</Link>
        </footer>
      </article>
    </main>
  );
}

