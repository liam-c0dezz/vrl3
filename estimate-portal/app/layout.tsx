import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") || requestHeaders.get("host");
  const protocol = requestHeaders.get("x-forwarded-proto") || "https";
  const origin = host ? `${protocol}://${host}` : "http://localhost:3000";

  return {
    title: "Estimate ready for review | EasyBid",
    description: "Review, download, request a change, or approve your estimate securely.",
    robots: {
      index: false,
      follow: false,
    },
    icons: {
      icon: "/favicon.svg",
      shortcut: "/favicon.svg",
    },
    openGraph: {
      title: "Estimate ready for review",
      description: "Review and approve your estimate securely with EasyBid.",
      images: [{ url: `${origin}/og.png`, width: 1200, height: 630 }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Estimate ready for review",
      description: "Review and approve your estimate securely with EasyBid.",
      images: [`${origin}/og.png`],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
