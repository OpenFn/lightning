-- Truncate all user data from Lightning database
-- This preserves schema structure while clearing all data
-- Designed to be faster than drop/create/migrate cycle

-- Note: We need to be careful about the order due to foreign key constraints
-- The strategy is to:
-- 1. Temporarily disable triggers (for performance)
-- 2. Truncate leaf tables first (tables that are referenced by others)
-- 3. Work up the dependency chain
-- 4. Use CASCADE where needed for circular references

-- Disable triggers for performance during mass truncation
SET session_replication_role = replica;

-- Start with the most dependent tables (leaves of the dependency tree)
-- These tables reference other tables but are not referenced themselves

-- AI Chat System (leaf tables)
TRUNCATE ai_chat_messages CASCADE;
TRUNCATE ai_chat_sessions CASCADE;

-- Audit and logging (leaf tables) 
TRUNCATE audit_events CASCADE;

-- All log_lines partitions (referenced by runs/steps but no other tables reference them)
TRUNCATE log_lines CASCADE;
TRUNCATE log_lines_1, log_lines_2, log_lines_3, log_lines_4, log_lines_5, 
         log_lines_6, log_lines_7, log_lines_8, log_lines_9, log_lines_10,
         log_lines_11, log_lines_12, log_lines_13, log_lines_14, log_lines_15,
         log_lines_16, log_lines_17, log_lines_18, log_lines_19, log_lines_20,
         log_lines_21, log_lines_22, log_lines_23, log_lines_24, log_lines_25,
         log_lines_26, log_lines_27, log_lines_28, log_lines_29, log_lines_30,
         log_lines_31, log_lines_32, log_lines_33, log_lines_34, log_lines_35,
         log_lines_36, log_lines_37, log_lines_38, log_lines_39, log_lines_40,
         log_lines_41, log_lines_42, log_lines_43, log_lines_44, log_lines_45,
         log_lines_46, log_lines_47, log_lines_48, log_lines_49, log_lines_50,
         log_lines_51, log_lines_52, log_lines_53, log_lines_54, log_lines_55,
         log_lines_56, log_lines_57, log_lines_58, log_lines_59, log_lines_60,
         log_lines_61, log_lines_62, log_lines_63, log_lines_64, log_lines_65,
         log_lines_66, log_lines_67, log_lines_68, log_lines_69, log_lines_70,
         log_lines_71, log_lines_72, log_lines_73, log_lines_74, log_lines_75,
         log_lines_76, log_lines_77, log_lines_78, log_lines_79, log_lines_80,
         log_lines_81, log_lines_82, log_lines_83, log_lines_84, log_lines_85,
         log_lines_86, log_lines_87, log_lines_88, log_lines_89, log_lines_90,
         log_lines_91, log_lines_92, log_lines_93, log_lines_94, log_lines_95,
         log_lines_96, log_lines_97, log_lines_98, log_lines_99, log_lines_100,
         log_lines_monolith CASCADE;

-- Collection system
TRUNCATE collection_items CASCADE;
TRUNCATE collections CASCADE;

-- Usage tracking system
TRUNCATE usage_tracking_reports CASCADE;
TRUNCATE usage_tracking_daily_report_configurations CASCADE;

-- User authentication related (leaf tables)
TRUNCATE user_backup_codes CASCADE;
TRUNCATE user_tokens CASCADE;
TRUNCATE user_totps CASCADE;

-- Trigger and webhook auth
TRUNCATE trigger_kafka_message_records CASCADE;
TRUNCATE trigger_webhook_auth_methods CASCADE;
TRUNCATE webhook_auth_methods CASCADE;

-- Project related leaf tables
TRUNCATE project_files CASCADE;
TRUNCATE project_repo_connections CASCADE;
TRUNCATE project_oauth_clients CASCADE;

-- OAuth system
TRUNCATE oauth_tokens CASCADE;

-- Run execution system (depends on workflows/jobs)
TRUNCATE run_steps CASCADE;
TRUNCATE steps CASCADE;
TRUNCATE runs CASCADE;
TRUNCATE work_orders CASCADE;

-- Workflow system (interdependent, using CASCADE)
TRUNCATE workflow_edges CASCADE;
TRUNCATE workflow_snapshots CASCADE;  
TRUNCATE workflow_versions CASCADE;
TRUNCATE workflow_templates CASCADE;
TRUNCATE jobs CASCADE;
TRUNCATE triggers CASCADE;
TRUNCATE workflows CASCADE;

-- Credential system
TRUNCATE keychain_credentials CASCADE;
TRUNCATE project_credentials CASCADE;
TRUNCATE credentials CASCADE;

-- Project membership
TRUNCATE project_users CASCADE;

-- Data storage
TRUNCATE dataclips CASCADE;
TRUNCATE collaboration_document_states CASCADE;

-- Background job system
TRUNCATE oban_jobs CASCADE;
TRUNCATE oban_peers CASCADE;

-- Core entities (these are referenced by many other tables)
TRUNCATE projects CASCADE;
TRUNCATE oauth_clients CASCADE;
TRUNCATE auth_providers CASCADE;
TRUNCATE users CASCADE;

-- Re-enable triggers
SET session_replication_role = DEFAULT;

-- Reset sequences to start from 1
-- Note: Only resetting sequences for tables that use SERIAL/BIGSERIAL
-- UUIDs don't need sequence resets

-- This query will generate the reset commands for all sequences
-- Run this after truncation to reset AUTO INCREMENT values
DO $$
DECLARE
    seq_record RECORD;
BEGIN
    FOR seq_record IN 
        SELECT sequence_name 
        FROM information_schema.sequences 
        WHERE sequence_schema = 'public'
          AND sequence_name NOT LIKE '%_pkey_seq'  -- Skip PK sequences for UUID tables
    LOOP
        EXECUTE format('ALTER SEQUENCE %I RESTART WITH 1', seq_record.sequence_name);
    END LOOP;
END $$;

-- Verify truncation worked (should return 0 for all tables with data)
-- Uncomment these lines to verify the truncation worked:
-- SELECT 'users' as table_name, count(*) as row_count FROM users
-- UNION ALL SELECT 'projects', count(*) FROM projects  
-- UNION ALL SELECT 'workflows', count(*) FROM workflows
-- UNION ALL SELECT 'jobs', count(*) FROM jobs
-- UNION ALL SELECT 'runs', count(*) FROM runs
-- UNION ALL SELECT 'dataclips', count(*) FROM dataclips;

ANALYZE; -- Update table statistics after truncation