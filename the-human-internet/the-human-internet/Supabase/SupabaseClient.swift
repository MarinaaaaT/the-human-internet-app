//
//  SupabaseClient.swift
//  the-human-internet
//

import Foundation
import Supabase

enum SupabaseConfig {
    static let url = URL(string: "https://xpjkgngifffzdaikjakw.supabase.co")!
    // Publishable key — safe to embed in client code, RLS enforces access control.
    static let publishableKey = "sb_publishable_tmrKLSHCT0-ZeCFTsPxQEg_Qijh19mI"
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.publishableKey
)
