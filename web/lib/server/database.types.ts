// Generated from the live Supabase schema (project jaajkutdglblwtpfcgag) with the Supabase MCP
// generate_typescript_types, 20 November 2026. Regenerate after every migration; see docs/pro/BACKEND.md.
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      blocks: {
        Row: {
          created_at: string
          id: string
          owner_id: string
          session_id: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          owner_id: string
          session_id?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          owner_id?: string
          session_id?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      comments: {
        Row: {
          at_s: number | null
          author_name: string
          author_user_id: string | null
          body: string
          created_at: string
          deleted_at: string | null
          held: boolean
          id: string
          parent_id: string | null
          session_id: string
          video_id: string
        }
        Insert: {
          at_s?: number | null
          author_name: string
          author_user_id?: string | null
          body: string
          created_at?: string
          deleted_at?: string | null
          held?: boolean
          id?: string
          parent_id?: string | null
          session_id: string
          video_id: string
        }
        Update: {
          at_s?: number | null
          author_name?: string
          author_user_id?: string | null
          body?: string
          created_at?: string
          deleted_at?: string | null
          held?: boolean
          id?: string
          parent_id?: string | null
          session_id?: string
          video_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_video_id_fkey"
            columns: ["video_id"]
            isOneToOne: false
            referencedRelation: "videos"
            referencedColumns: ["id"]
          },
        ]
      }
      devices: {
        Row: {
          app_version: string | null
          created_at: string
          environment: Database["public"]["Enums"]["push_environment"]
          last_seen_at: string
          token: string
          user_id: string
        }
        Insert: {
          app_version?: string | null
          created_at?: string
          environment?: Database["public"]["Enums"]["push_environment"]
          last_seen_at?: string
          token: string
          user_id: string
        }
        Update: {
          app_version?: string | null
          created_at?: string
          environment?: Database["public"]["Enums"]["push_environment"]
          last_seen_at?: string
          token?: string
          user_id?: string
        }
        Relationships: []
      }
      notification_log: {
        Row: {
          created_at: string
          dedupe_key: string
          id: string
          kind: string
          user_id: string
          video_id: string | null
        }
        Insert: {
          created_at?: string
          dedupe_key: string
          id?: string
          kind: string
          user_id: string
          video_id?: string | null
        }
        Update: {
          created_at?: string
          dedupe_key?: string
          id?: string
          kind?: string
          user_id?: string
          video_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_log_video_id_fkey"
            columns: ["video_id"]
            isOneToOne: false
            referencedRelation: "videos"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          brand_color: string | null
          brand_logo_path: string | null
          created_at: string
          display_name: string | null
          email_alerts: boolean
          id: string
        }
        Insert: {
          brand_color?: string | null
          brand_logo_path?: string | null
          created_at?: string
          display_name?: string | null
          email_alerts?: boolean
          id: string
        }
        Update: {
          brand_color?: string | null
          brand_logo_path?: string | null
          created_at?: string
          display_name?: string | null
          email_alerts?: boolean
          id?: string
        }
        Relationships: []
      }
      reactions: {
        Row: {
          at_s: number
          author_name: string | null
          author_user_id: string | null
          created_at: string
          emoji: string
          id: string
          session_id: string
          video_id: string
        }
        Insert: {
          at_s?: number
          author_name?: string | null
          author_user_id?: string | null
          created_at?: string
          emoji: string
          id?: string
          session_id: string
          video_id: string
        }
        Update: {
          at_s?: number
          author_name?: string | null
          author_user_id?: string | null
          created_at?: string
          emoji?: string
          id?: string
          session_id?: string
          video_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reactions_video_id_fkey"
            columns: ["video_id"]
            isOneToOne: false
            referencedRelation: "videos"
            referencedColumns: ["id"]
          },
        ]
      }
      reports: {
        Row: {
          created_at: string
          details: string
          email: string | null
          id: string
          reason: Database["public"]["Enums"]["report_reason"]
          resolved_at: string | null
          video_id: string
        }
        Insert: {
          created_at?: string
          details?: string
          email?: string | null
          id?: string
          reason: Database["public"]["Enums"]["report_reason"]
          resolved_at?: string | null
          video_id: string
        }
        Update: {
          created_at?: string
          details?: string
          email?: string | null
          id?: string
          reason?: Database["public"]["Enums"]["report_reason"]
          resolved_at?: string | null
          video_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reports_video_id_fkey"
            columns: ["video_id"]
            isOneToOne: false
            referencedRelation: "videos"
            referencedColumns: ["id"]
          },
        ]
      }
      subscriptions: {
        Row: {
          environment: Database["public"]["Enums"]["store_environment"]
          expires_at: string | null
          original_transaction_id: string
          product_id: string
          status: Database["public"]["Enums"]["subscription_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          environment: Database["public"]["Enums"]["store_environment"]
          expires_at?: string | null
          original_transaction_id: string
          product_id: string
          status: Database["public"]["Enums"]["subscription_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          environment?: Database["public"]["Enums"]["store_environment"]
          expires_at?: string | null
          original_transaction_id?: string
          product_id?: string
          status?: Database["public"]["Enums"]["subscription_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      videos: {
        Row: {
          access: Database["public"]["Enums"]["video_access"]
          allow_comments: boolean
          allow_download: boolean
          allow_reactions: boolean
          created_at: string
          cta: Json | null
          deleted_at: string | null
          duration_s: number
          expires_at: string | null
          height: number
          id: string
          kind: Database["public"]["Enums"]["video_kind"]
          local_id: string
          owner_id: string
          password_hash: string | null
          size_bytes: number
          slug: string
          status: Database["public"]["Enums"]["video_status"]
          title: string
          transcript: Json | null
          updated_at: string
          uploaded_bytes: number
          width: number
        }
        Insert: {
          access?: Database["public"]["Enums"]["video_access"]
          allow_comments?: boolean
          allow_download?: boolean
          allow_reactions?: boolean
          created_at?: string
          cta?: Json | null
          deleted_at?: string | null
          duration_s: number
          expires_at?: string | null
          height?: number
          id?: string
          kind: Database["public"]["Enums"]["video_kind"]
          local_id: string
          owner_id: string
          password_hash?: string | null
          size_bytes?: number
          slug: string
          status?: Database["public"]["Enums"]["video_status"]
          title?: string
          transcript?: Json | null
          updated_at?: string
          uploaded_bytes?: number
          width?: number
        }
        Update: {
          access?: Database["public"]["Enums"]["video_access"]
          allow_comments?: boolean
          allow_download?: boolean
          allow_reactions?: boolean
          created_at?: string
          cta?: Json | null
          deleted_at?: string | null
          duration_s?: number
          expires_at?: string | null
          height?: number
          id?: string
          kind?: Database["public"]["Enums"]["video_kind"]
          local_id?: string
          owner_id?: string
          password_hash?: string | null
          size_bytes?: number
          slug?: string
          status?: Database["public"]["Enums"]["video_status"]
          title?: string
          transcript?: Json | null
          updated_at?: string
          uploaded_bytes?: number
          width?: number
        }
        Relationships: []
      }
      views: {
        Row: {
          buckets: unknown
          completed: boolean
          counted: boolean
          country: string | null
          device: Database["public"]["Enums"]["device_kind"] | null
          id: string
          last_seen_at: string
          max_position_s: number
          referrer_host: string | null
          session_id: string
          started_at: string
          video_id: string
          viewer_name: string | null
          viewer_user_id: string | null
          watched_s: number
        }
        Insert: {
          buckets?: unknown
          completed?: boolean
          counted?: boolean
          country?: string | null
          device?: Database["public"]["Enums"]["device_kind"] | null
          id?: string
          last_seen_at?: string
          max_position_s?: number
          referrer_host?: string | null
          session_id: string
          started_at?: string
          video_id: string
          viewer_name?: string | null
          viewer_user_id?: string | null
          watched_s?: number
        }
        Update: {
          buckets?: unknown
          completed?: boolean
          counted?: boolean
          country?: string | null
          device?: Database["public"]["Enums"]["device_kind"] | null
          id?: string
          last_seen_at?: string
          max_position_s?: number
          referrer_host?: string | null
          session_id?: string
          started_at?: string
          video_id?: string
          viewer_name?: string | null
          viewer_user_id?: string | null
          watched_s?: number
        }
        Relationships: [
          {
            foreignKeyName: "views_video_id_fkey"
            columns: ["video_id"]
            isOneToOne: false
            referencedRelation: "videos"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      active_link_count: { Args: { uid: string }; Returns: number }
      is_pro: { Args: { uid: string }; Returns: boolean }
      prune_rate_limits: { Args: { p_before: string }; Returns: number }
      rate_limit_hit: {
        Args: { p_key: string; p_max: number; p_window_s: number }
        Returns: boolean
      }
      record_view: {
        Args: {
          p_country: string | null
          p_device: Database["public"]["Enums"]["device_kind"] | null
          p_duration: number
          p_event: string
          p_position: number
          p_referrer_host: string | null
          p_session_id: string
          p_video_id: string
          p_view_id: string | null
          p_viewer_name: string | null
          p_viewer_user_id: string | null
          p_watched: number[]
        }
        Returns: {
          counted: boolean
          first_for_session: boolean
          newly_counted: boolean
          percent: number
          view_id: string
        }[]
      }
      video_stats: {
        Args: { p_video_ids: string[] }
        Returns: {
          comment_count: number
          last_viewed_at: string | null
          unique_viewers: number
          video_id: string
          views: number
        }[]
      }
    }
    Enums: {
      device_kind: "phone" | "tablet" | "desktop"
      push_environment: "production" | "sandbox"
      report_reason: "spam" | "abuse" | "illegal" | "copyright" | "other"
      store_environment: "Production" | "Sandbox"
      subscription_status: "active" | "in_grace" | "expired" | "revoked"
      video_access: "link" | "password"
      video_kind: "screen" | "camera" | "audio"
      video_status: "uploading" | "ready" | "failed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type PublicSchema = Database["public"]

export type Tables<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Row"]
export type TablesInsert<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Insert"]
export type TablesUpdate<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Update"]
export type Enums<T extends keyof PublicSchema["Enums"]> = PublicSchema["Enums"][T]
