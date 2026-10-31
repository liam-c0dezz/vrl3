import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy | EasyBid",
  description:
    "How EasyBid collects, uses, shares, protects, retains, and deletes information.",
  robots: {
    index: true,
    follow: true,
  },
};

const effectiveDate = "July 31, 2026";

export default function PrivacyPolicyPage() {
  return (
    <main className="policy-page">
      <article className="policy-document">
        <header className="policy-header">
          <Link className="policy-brand" href="/" aria-label="EasyBid estimate portal">
            <span className="brand-mark">E</span>
            <span>EasyBid</span>
          </Link>
          <p className="eyebrow">Legal</p>
          <h1>Privacy Policy</h1>
          <p className="policy-effective">Effective and last updated: {effectiveDate}</p>
          <p className="policy-intro">
            This Privacy Policy explains how EasyBid (&quot;EasyBid,&quot;
            &quot;we,&quot; &quot;us,&quot; or &quot;our&quot;) handles
            information through the EasyBid iOS app, estimate-review portal,
            and related services (collectively, the &quot;Service&quot;).
          </p>
        </header>

        <nav className="policy-summary" aria-label="Privacy policy contents">
          <strong>At a glance</strong>
          <ul>
            <li>We use data to operate accounts, projects, AI estimates and renders, invoices, approvals, and subscriptions.</li>
            <li>We do not sell personal information or use it for cross-app advertising tracking.</li>
            <li>Camera access is optional and requested only when you take a job photo.</li>
            <li>AI features remain off until an account holder affirmatively allows them.</li>
            <li>You can delete your account and associated workspace data from inside the app.</li>
          </ul>
        </nav>

        <section>
          <h2>1. Scope and roles</h2>
          <p>
            This policy applies to people who create an EasyBid account, use the
            app, or open a secure estimate link. Contractors and businesses may
            enter information about their own clients, workers, properties, and
            projects. Those business users are responsible for having an
            appropriate basis to provide that information to EasyBid and for
            giving any notices their clients or workers require.
          </p>
        </section>

        <section>
          <h2>2. Information we collect</h2>
          <h3>Account and contact information</h3>
          <p>
            We may collect your name, email address, phone number, authentication
            provider, account identifier, and company or workspace name. Apple may
            provide limited profile information when you choose Sign in with Apple.
            We do not receive your Apple password or your email-account password.
          </p>

          <h3>Client, property, and project information</h3>
          <p>
            You may enter client names, companies, email addresses, phone numbers,
            physical addresses, referral sources, property details, project
            descriptions, job addresses, ZIP codes, assignments, notes, and
            statuses.
          </p>

          <h3>Estimates, invoices, and financial records</h3>
          <p>
            We collect the line items, quantities, prices, labor and material
            assumptions, markups, contingencies, totals, payment terms, invoice
            status, and related business records you create. EasyBid does not
            collect payment-card or bank-account numbers. Apple processes App
            Store subscription payments.
          </p>

          <h3>User content and AI inputs</h3>
          <p>
            Depending on the features you choose, we process chat prompts,
            project descriptions, screening answers, audio files,
            transcriptions, photographs, video frames and video audio, uploaded
            documents, and the AI-generated responses, estimates, and project renders created from
            them. Avoid submitting sensitive personal information that is not
            needed for a project.
          </p>

          <h3>Client portal information</h3>
          <p>
            A secure estimate link can display a snapshot containing the
            contractor&apos;s business name, client name and company, project
            address and description, estimate details, and line items. When a
            recipient views, approves, or requests a change, we record the action,
            name supplied by the recipient, message, status, and timestamps.
            The link functions as a confidential access credential: anyone who
            receives it may be able to view that estimate until the link expires
            or is revoked, so recipients should not forward or publish it.
          </p>

          <h3>Subscription, device, and usage information</h3>
          <p>
            Our subscription provider may process purchase history, subscription
            status, an app user identifier, vendor or device identifier, app and
            operating-system version, device model, locale, region inferred from
            IP address, paywall views, purchase events, and similar product
            interactions. Servers also receive standard technical information
            such as IP address, request time, and security logs.
          </p>

          <h3>Sources of information</h3>
          <p>
            We receive information directly from account holders and estimate
            recipients, automatically from devices and service requests, from
            Apple when selected for authentication, from Apple and Superwall for
            subscription events, and from contractors who enter
            information about their clients and projects.
          </p>
        </section>

        <section>
          <h2>3. Device permissions</h2>
          <ul>
            <li>
              <strong>Camera:</strong> requested when you choose to photograph a
              job or attach a camera image.
            </li>
          </ul>
          <p>
            You can deny camera permission and continue using features that do not
            require it, or change access later in iOS Settings. Photo, audio, video, and document
            selection use Apple&apos;s system pickers, which give EasyBid access
            only to items you select rather than broad access to your libraries.
            EasyBid does not request Contacts, precise Location, or push
            Notification permission.
          </p>
        </section>

        <section>
          <h2>4. How we use information</h2>
          <ul>
            <li>create and secure accounts and company workspaces;</li>
            <li>sync clients, projects, estimates, invoices, and documents;</li>
            <li>generate AI-assisted estimates and project visualizations;</li>
            <li>process photos, audio files, video frames and audio, and documents you intentionally select;</li>
            <li>create secure client-review links and record approval activity;</li>
            <li>provide subscriptions, paywalls, entitlement checks, and purchase restoration;</li>
            <li>personalize local pricing or feature presentation;</li>
            <li>measure product and paywall interactions and maintain reliability;</li>
            <li>detect abuse, prevent fraud, enforce terms, and comply with law; and</li>
            <li>respond to support, privacy, or legal requests.</li>
          </ul>
        </section>

        <section>
          <h2>5. How we disclose information</h2>
          <p>
            We disclose information only as needed to operate the Service, at your
            direction, or for legal and safety reasons. Current categories of
            recipients include:
          </p>
          <ul>
            <li><strong>Supabase</strong> for authentication, database, server functions, and file storage;</li>
            <li><strong>OpenAI</strong> to process text, images, and audio for AI-assisted features;</li>
            <li><strong>Superwall</strong> for paywalls, subscription status, and related product analytics;</li>
            <li><strong>Apple</strong> for App Store distribution, subscriptions, and Sign in with Apple;</li>
            <li><strong>Cloudflare and OpenAI Sites</strong> to deliver the secure estimate portal; and</li>
            <li>professional advisers, authorities, or transaction participants when reasonably necessary for legal compliance, safety, or a business transfer.</li>
          </ul>
          <p>
            When you choose Mail or Messages, the content and recipient you select
            are handled by Apple and your communications provider. Third-party
            processors that receive EasyBid user data must provide the same or
            equivalent protection described in this policy and required by
            applicable law. We do not sell personal information, share it with
            data brokers, or use it for targeted advertising across other
            companies&apos; apps or websites.
          </p>
        </section>

        <section>
          <h2>6. Artificial intelligence</h2>
          <p>
            Before the first AI Chat or Renders use, EasyBid asks you to allow AI features.
            If you allow them, EasyBid sends chat messages, relevant project
            information, and any photos, audio files, or videos you intentionally
            attach to OpenAI&apos;s API. Video is processed into representative
            frames and an audio transcript before it is submitted. OpenAI uses
            this material to classify jobs, transcribe or interpret content,
            generate responses, and create project visualizations. API content is not used to train
            OpenAI models by default. OpenAI may retain API content or
            abuse-monitoring data for up to 30 days, or longer when legally
            required. AI results can be inaccurate and should be reviewed by a
            qualified person before being relied on or sent to a client.
          </p>
          <p>
            Your choice and the applicable notice version are recorded with your
            account. You can withdraw or restore AI permission in the app&apos;s
            Privacy &amp; Permissions screen. Withdrawing permission prevents new
            OpenAI requests; non-AI EasyBid features remain available.
          </p>
        </section>

        <section>
          <h2>7. Retention</h2>
          <p>
            Account and workspace records are generally retained while your
            account is active. Local chat history and preferences remain on your
            device until you clear them, delete the account, or remove the app.
            Estimate share links normally expire after 30 days, although approval
            records and underlying business records may remain with the
            contractor&apos;s workspace. Service providers may retain limited
            security, transaction, or backup records under their own retention
            schedules. We may retain information longer when required to comply
            with law, resolve disputes, prevent fraud, or enforce agreements.
          </p>
          <p>
            When you delete your account in the app, EasyBid deletes the account,
            its owned workspace records, and associated uploaded project files,
            subject to legal obligations and limited residual backups. Deleting
            EasyBid does not automatically cancel an Apple subscription.
          </p>
        </section>

        <section id="your-choices">
          <h2>8. Your choices and privacy rights</h2>
          <ul>
            <li>Change Camera permission in iOS Settings.</li>
            <li>Withdraw or restore AI permission in EasyBid&apos;s Privacy &amp; Permissions screen.</li>
            <li>To cancel, open iPhone Settings, tap your name, choose Subscriptions, select EasyBid, and tap Cancel Subscription.</li>
            <li>Delete your account from the EasyBid account menu.</li>
            <li>Revoke EasyBid&apos;s Apple account access through Apple&apos;s settings.</li>
            <li>Ask to access, correct, export, restrict, object to, or delete personal information through EasyBid Support.</li>
          </ul>
          <p>
            Depending on where you live, you may have additional rights, including
            appeal or complaint rights. We may verify your identity before
            completing a request. Authorized agents may submit requests where
            permitted by law. We will not discriminate against you for exercising
            a privacy right.
          </p>
          <p>
            EasyBid does not sell or share personal information for cross-context
            behavioral advertising and therefore does not offer a sale/sharing
            opt-out.
          </p>
        </section>

        <section>
          <h2>9. Supplemental United States privacy notice</h2>
          <p>
            During the preceding 12 months, EasyBid may have collected the
            categories described above: identifiers and contact information;
            customer and commercial records; coarse location; internet or
            electronic activity; audio, visual, and other user content;
            professional or employment-related project information; and
            inferences produced for estimate assistance. Sources, business
            purposes, and recipient categories are described in Sections 2, 4,
            and 5.
          </p>
          <p>
            Subject to local law, residents may request access, correction,
            deletion, or portability; opt out of qualifying sale, sharing, or
            targeted advertising; limit certain sensitive-data uses; and appeal
            a denied request. EasyBid does not sell personal information, share
            it for cross-context behavioral advertising, or use it for targeted
            advertising. We will not discriminate against a person for
            exercising an applicable privacy right.
          </p>
        </section>

        <section>
          <h2>10. Legal bases and international processing</h2>
          <p>
            Where applicable, we process information to perform our contract with
            you, with consent, to comply with law, and for legitimate interests
            such as securing and improving the Service that are not overridden by
            your rights. EasyBid and its providers may process information in the
            United States and other countries, using legally recognized safeguards
            where required.
          </p>
        </section>

        <section>
          <h2>11. Security</h2>
          <p>
            We use administrative, technical, and organizational safeguards
            designed to protect information, including encrypted network
            connections, authenticated access, database row-level access
            controls, hashed high-entropy portal tokens, expiring and revocable
            estimate links, restricted browser permissions, and controls intended
            to prevent caching or indexing of estimate pages. No system is
            completely secure, so we cannot guarantee absolute security.
          </p>
        </section>

        <section>
          <h2>12. Children</h2>
          <p>
            EasyBid is a business service and is not directed to children under
            13. We do not knowingly collect personal information from children
            under 13. Contact us if you believe a child has provided information
            to the Service.
          </p>
        </section>

        <section>
          <h2>13. Changes to this policy</h2>
          <p>
            We may update this policy as the Service or law changes. We will post
            the revised version here and change the effective date. We will
            provide additional notice when required by law.
          </p>
        </section>

        <section>
          <h2>14. Contact us</h2>
          <p>
            For privacy questions or requests, contact EasyBid Privacy Support
            through our <Link href="/support">Support page</Link>. We may verify
            a request before acting on it.
          </p>
        </section>

        <footer className="policy-footer">
          <span>© {new Date().getFullYear()} EasyBid</span>
          <Link href="/">Estimate portal</Link>
          <Link href="/support">Support</Link>
          <Link href="/terms">Terms of Use</Link>
          <a href="#your-choices">Privacy choices</a>
        </footer>
      </article>
    </main>
  );
}
