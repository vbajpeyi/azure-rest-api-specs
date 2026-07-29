// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.

import "../openai-responses/models.tsp";

using TypeSpec.OpenAPI;
using Azure.Core;

namespace Azure.AI.Projects;

const AgentServerPersistenceContract = #{
  contract: "agentserver-persistence",
  usage: "cross-language-sdk-persistence",
};

const AgentServerPersistenceRequiredPreviews = #{
  ...AgentServerPersistenceContract,
  required_previews: #[FoundryFeaturesOptInKeys.routines_v1_preview],
};

// ---------------------------------------------------------------------------
// AgentServer Core durable task persistence contract
// ---------------------------------------------------------------------------

/** Status values persisted on an AgentServer durable task record. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
union AgentServerTaskStatus {
  pending: "pending",
  inProgress: "in_progress",
  suspended: "suspended",
  completed: "completed",
}

/**
 * Lease details on an AgentServer durable task record.
 * The lease is the optimistic ownership/fencing token for a single worker instance.
 */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskLease {
  /** Stable lease owner, typically scoped to the agent and session. */
  owner: string;

  /** Ephemeral worker instance identifier. */
  instance_id: string;

  /** Fencing generation. Increments whenever a different instance re-acquires the lease. */
  generation: int64 = 0;

  /** ISO 8601 UTC instant after which the lease is expired. */
  expires_at: string;

  /** Number of times ownership changed via expiry. */
  expiry_count: int64 = 0;

  /**
   * ISO 8601 UTC instant of the most recent provider-stamped lease heartbeat.
   * Implementations may omit this field until heartbeat telemetry is enabled.
   */
  heartbeat_at?: string;
}

/**
 * Provenance and recovery-routing metadata for an AgentServer durable task record.
 */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskSource {
  /** Source discriminator. For SDK-owned resilient tasks this is typically `agentserver.task`. */
  @maxLength(64)
  type: string;

  /** Registered task name used by SDK-owned tasks to route a recovered task to its handler. */
  name?: string;

  /** SDK/runtime version string that created the task record. */
  server_version?: string;

  /** Foundry hosting environment value captured when the task was created, or empty for local execution. */
  hosting_environment?: string;

  /** Forward-compatible source extension fields. */
  ...Record<unknown>;
}

/** Reference to a task attachment that replaced an oversized inline JSON payload slot. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskAttachmentRef {
  /** Attachment key in the companion attachment map. */
  key: string;

  /** Content hash in `sha256:<64 lowercase hex>` format. */
  hash: string;
}

/** Single-key attachment reference envelope persisted in payload slots. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskAttachmentRefEnvelope {
  /** Attachment reference marker and payload. */
  __attachment_ref__: AgentServerTaskAttachmentRef;
}

/** Common task payload fields carrying framework-reserved metadata plus feature-specific JSON. */
alias AgentServerTaskPayloadCommon = {
  /** Default metadata namespace for durable checkpoints. */
  metadata?: Record<unknown>;

  /** Last input id processed by this task chain. */
  last_input_id?: string;

  /** ISO 8601 UTC timestamp when the current turn started. */
  turn_started_at?: string;

  /** Current retry attempt for the active turn. */
  retry_attempt?: int32 | null;

  /** Durable steering queue state. */
  steering?: Record<unknown>;

  /** Task document schema version. */
  schema_version?: string;

  /** Feature-specific payload fields. */
  ...Record<unknown>;
};

/** Common task payload shape carrying framework-reserved fields plus feature-specific JSON. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskPayload {
  /** Current turn input or an attachment-reference envelope. */
  input?: unknown;

  ...AgentServerTaskPayloadCommon;
}

/** Responses resilient task input can be inline recovery data or an attachment reference. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
union AgentServerResponseTaskInput {
  recoveryPayload: AgentServerResponseRecoveryPayload,
  attachmentRef: AgentServerTaskAttachmentRefEnvelope,
}

/** Payload shape used by resilient Responses tasks. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerResponseTaskPayload {
  /** Resilient response input persisted under the task payload's `input` slot. */
  input: AgentServerResponseTaskInput;

  ...AgentServerTaskPayloadCommon;
}

/** Task payload value. Most callers use arbitrary JSON; Responses resilience has a documented input shape. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
union AgentServerTaskPayloadValue {
  arbitrary: unknown,
  responseRecovery: AgentServerResponseTaskPayload,
}

/**
 * Persisted AgentServer durable task record shared by Python and .NET SDK implementations.
 */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskRecord {
  /** Envelope discriminator. Always `task`. */
  object: "task";

  /** Stable task identifier. */
  id: string;

  /** Agent scope that owns this task. */
  agent_name: string;

  /** Session scope that owns this task. */
  session_id: string;

  /** Current task status. */
  status: AgentServerTaskStatus;

  /** Human-readable title. */
  @maxLength(256)
  title: string;

  /** Optional human-readable description. */
  @maxLength(1024)
  description: string | null;

  /** Active lease details, or null when no lease is held. */
  lease: AgentServerTaskLease | null;

  /**
   * Task payload. Contains framework-reserved keys such as `input`, `metadata`,
   * `last_input_id`, `turn_started_at`, `retry_attempt`, `steering`, and
   * `schema_version`, plus feature-specific JSON data.
   */
  payload: AgentServerTaskPayloadValue | null;

  /** Same-scope task dependencies. Pending tasks are ready when every dependency is completed. */
  depends_on_task_ids: string[];

  /** String tags associated with this task. */
  tags: Record<string> | null;

  /** Source/provenance metadata used for recovery routing. */
  source: AgentServerTaskSource | null;

  /** Promoted attachment values keyed by attachment key. */
  attachments: Record<unknown> | null;

  /** Structured terminal error details. */
  error: AgentServerTaskError | null;

  /** Reason the task was suspended. */
  @maxLength(256)
  suspension_reason: string | null;

  /** ISO 8601 UTC creation timestamp. */
  created_at: string;

  /** ISO 8601 UTC last-update timestamp. */
  updated_at: string;

  /** ISO 8601 UTC timestamp of the first transition to `in_progress`, or null. */
  started_at: string | null;

  /** ISO 8601 UTC completion timestamp, or null. */
  completed_at: string | null;

  /** Optimistic-concurrency token. */
  etag: string;
}

/** Request body for creating an AgentServer durable task record. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskCreateRequest {
  /** Optional caller-supplied task identifier. If omitted, the provider generates one. */
  id?: string;

  /** Agent scope that owns this task. */
  agent_name: string;

  /** Session scope that owns this task. */
  session_id: string;

  /** Human-readable title. */
  @maxLength(256)
  title: string;

  /** Optional human-readable description. */
  @maxLength(1024)
  description?: string;

  /** Initial task status. Defaults to `pending`. */
  status?: AgentServerTaskStatus = AgentServerTaskStatus.pending;

  /** Initial task payload. */
  payload?: AgentServerTaskPayloadValue;

  /** Same-scope task dependencies. Immutable after creation. */
  depends_on_task_ids?: string[];

  /** Initial string tags. */
  tags?: Record<string>;

  /** Source/provenance metadata used for recovery routing. */
  source?: AgentServerTaskSource;

  /** Initial promoted attachment values keyed by attachment key. */
  attachments?: Record<unknown>;
}

/** Request body for patching an AgentServer durable task record. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskPatchRequest {
  /** New status, if transitioning task state. */
  status?: AgentServerTaskStatus;

  /**
   * Payload patch. Object values are shallow-merged by the provider; non-object
   * values replace the full payload.
   */
  payload?: AgentServerTaskPayloadValue;

  /** Tag patch. Null values delete keys. */
  tags?: Record<unknown>;

  /** Attachment patch. Null values delete keys; top-level null clears all attachments. */
  attachments?: Record<unknown> | null;

  /** Structured terminal error details. */
  error?: AgentServerTaskError | null;

  /** Suspension reason when transitioning to `suspended`. */
  @maxLength(256)
  suspension_reason?: string;
}

/** Structured error persisted on a task record. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskError {
  /** Error type discriminator, such as `timeout` or `retries_exhausted`. */
  type: string;

  /** Human-readable error message. */
  message: string;

  /** Optional machine-readable error code. Defaults to `error` when omitted by the caller. */
  code?: string = "error";

  /** Additional structured error fields. */
  ...Record<unknown>;
}

/** Cursor-paged list response for AgentServer durable task records. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerTaskListResponse {
  /** Object discriminator. Always `list`. */
  object: "list";

  /** Page of matching task records. */
  @pageItems
  data: AgentServerTaskRecord[];

  /** First task id represented in this page. */
  first_id?: string;

  /** Whether more records are available. */
  has_more: boolean;

  /** Cursor to pass as `after` for the next page when `has_more` is true. */
  @continuationToken
  last_id?: string;
}

// ---------------------------------------------------------------------------
// AgentServer Responses resilience persistence contract
// ---------------------------------------------------------------------------

/** Recovery disposition for a persisted response task input. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
union AgentServerResponseRecoveryDisposition {
  reinvoke: "re-invoke",
  markFailed: "mark-failed",
}

/** Agent reference payload persisted in a response recovery record. */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
union AgentServerResponseAgentReferencePayload {
  agentReference: AgentReference,
  extension: Record<unknown>,
}

/**
 * Persisted response recovery payload shared by Python `ResilientResponseInput`
 * and .NET `ResponseRecoveryPayload`.
 */
@extension("x-ms-foundry-meta", AgentServerPersistenceContract)
model AgentServerResponseRecoveryPayload {
  /** Stable response identifier to recover or mark failed. */
  response_id: string;

  /** Recovery disposition. Defaults to `re-invoke` when absent in older records. */
  disposition?: AgentServerResponseRecoveryDisposition = AgentServerResponseRecoveryDisposition.reinvoke;

  /** Original CreateResponse request. Re-derived response fields use this as the source of truth. */
  request: OpenAI.CreateResponse;

  /** Normalized agent reference captured at response creation. Empty object means absent. */
  agent_reference?: AgentServerResponseAgentReferencePayload;

  /** Agent session id captured at response creation, when available. */
  agent_session_id?: string;

  /** Platform user identity partition key captured at response creation, when available. */
  user_id_key?: string;

  /** Platform call id captured at response creation, when available. */
  call_id?: string;

  /** Forwarded client request headers captured at response creation. */
  client_headers: Record<string>;

  /** Request query parameters captured at response creation. */
  query_parameters: Record<string>;
}
