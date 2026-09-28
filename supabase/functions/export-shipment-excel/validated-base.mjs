// Only reuse a BASE whose saved bytes were verified against the current DB
// revision. Deployment IDs may differ when only download handling changed.
export function canReuseValidatedBase(template, sync, version) {
 const policy=template?.policy_summary, integrity=policy?.integrity;
 return Boolean(template?.storage_path && !template.storage_path.startsWith('database://') &&
  sync?.status==='ready' && Number(sync.revision)>0 &&
  Number(sync.completed_revision)===Number(sync.revision) &&
  policy?.automation_version===version &&
  Number(policy.validated_source_revision)===Number(sync.revision) &&
  integrity?.stored_download_verified===true && integrity.shared_formula_errors===0);
}
