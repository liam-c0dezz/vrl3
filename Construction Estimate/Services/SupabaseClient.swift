//
//  SupabaseClient.swift
//  Construction Estimate
//
//  Shared Supabase client. Every read or write to Supabase from the app
//  goes through the global `supabase` instance defined at the bottom of
//  this file.
//
//  Usage example:
//      let rows: [EstimateItemRow] = try await supabase
//          .from("estimate_items")
//          .select()
//          .eq("estimate_id", value: estimateID)
//          .execute()
//          .value
//

import Foundation
import Supabase

enum SupabaseConfig {
    /// The Supabase project's base URL.
    static let url = URL(string: "https://tuykoxmpnmrawrknjikr.supabase.co")!

    /// The **publishable** (public) key. Safe to embed in the client app —
    /// this is the key Supabase designed for client-side use. It is NOT the
    /// `sb_secret_…` service-role key (that one must never live in the app).
    static let publishableKey = "sb_publishable_mYhHJdb0mfCTvUWdGAWrpg_jmbY9GV-"

    /// Registered in Info.plist and in Supabase Auth's redirect allowlist.
    static let authCallbackURL = URL(
        string: "com.constructionestimate.Construction-Estimate://auth-callback"
    )!
    static let passwordRecoveryURL = URL(
        string: "com.constructionestimate.Construction-Estimate://reset-password"
    )!
}

/// Single shared Supabase client for the whole app.
let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.publishableKey,
    options: SupabaseClientOptions(
        auth: .init(redirectToURL: SupabaseConfig.authCallbackURL)
    )
)
