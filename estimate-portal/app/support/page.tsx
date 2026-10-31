import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Support | EasyBid",
  description:
    "Contact EasyBid support for account, estimate, subscription, privacy, or technical help.",
  robots: {
    index: true,
    follow: true,
  },
};

const supportEmail = "jack@viralappdev.com";

export default function SupportPage() {
  return (
    <main className="policy-page">
      <article className="policy-document support-document">
        <header className="policy-header">
          <Link className="policy-brand" href="/" aria-label="EasyBid estimate portal">
            <span className="brand-mark">E</span>
            <span>EasyBid</span>
          </Link>
          <p className="eyebrow">Help</p>
          <h1>EasyBid Support</h1>
          <p className="policy-intro">
            Get help with your account, estimates, invoices, client approvals,
            subscriptions, privacy requests, or technical problems.
          </p>
        </header>

        <section>
          <h2>Contact support</h2>
          <p>
            Email{" "}
            <a href={`mailto:${supportEmail}?subject=EasyBid%20Support`}>
              {supportEmail}
            </a>
            . Include the email address on your EasyBid account and a brief
            description of the problem. Do not send passwords, payment-card
            numbers, secure estimate links, or unnecessary client information.
          </p>
          <p>Support requests are reviewed as soon as reasonably possible.</p>
        </section>

        <section>
          <h2>Account and privacy requests</h2>
          <p>
            You can delete your account and associated workspace data from the
            EasyBid account menu. For access, correction, export, deletion, or
            other privacy requests, email support with the subject “Privacy
            Request.” We may verify your identity before completing a request.
          </p>
        </section>

        <section>
          <h2>Subscriptions and billing</h2>
          <p>
            App Store subscriptions are billed by Apple. You can manage or
            cancel a subscription by opening iPhone Settings, tapping your name,
            choosing Subscriptions, selecting EasyBid, and tapping Cancel
            Subscription.
            Deleting EasyBid does not automatically cancel an Apple
            subscription.
          </p>
        </section>

        <section>
          <h2>Estimate recipients</h2>
          <p>
            If you received an EasyBid estimate, contact the contractor who sent
            it for questions about pricing, scope, scheduling, or requested
            changes. Contact EasyBid Support only for technical or privacy
            problems with the portal.
          </p>
        </section>

        <footer className="policy-footer">
          <span>© {new Date().getFullYear()} EasyBid</span>
          <Link href="/">Estimate portal</Link>
          <Link href="/privacy">Privacy Policy</Link>
          <Link href="/terms">Terms of Use</Link>
        </footer>
      </article>
    </main>
  );
}
