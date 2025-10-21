local esp = import 'espejote.libsonnet';
local config = import 'lib/espejote-rbac-sync/config.json';

local context = esp.context();

local activeSetsAnnotation = 'rbac.syn.tools/active-policies';

// Extract the active template sets from the given namespace object,
// based on the annotations applied by this ManagedResource.
local activeTemplateSets(namespace) =
  local rawSet = std.get(std.get(namespace.metadata, 'annotations', {}), activeSetsAnnotation, '[]');
  std.set(std.parseJson(rawSet));

// Extract the desired template sets from the given namespace object,
// Returns an empty array if the namespace is in the ignoreNames or ignorePrefixes list.
local desiredTemplateSets(namespace) =
  local objHasLabel(obj, label) =
    std.objectHas(std.get(obj.metadata, 'labels', {}), label);

  // Check if the namespace is ignored by name or prefix.
  local isIgnored(namespace) =
    std.member(config.ignoreNames, namespace.metadata.name) ||
    std.length(
      std.filter(
        function(prefix) std.startsWith(namespace.metadata.name, prefix),
        config.ignorePrefixes
      )
    ) > 0;

  // Template sets based on labels starting with params.labelPrefix.
  //   labels:
  //     set.example.io/airlock: ""
  //     set.example.io/myapp: ""
  // would return the template sets `["airlock", "myapp"]`.
  // The configured prefix is suffixed with a '/' if it does not already end with one.
  local templateSetsFromLabel =
    local prefix = if std.endsWith(config.labelPrefix, '/') then
      config.labelPrefix
    else
      config.labelPrefix + '/';

    [
      lbl[std.length(prefix):]
      for lbl in std.objectFields(std.get(namespace.metadata, 'labels', {}))
      if std.startsWith(lbl, prefix)
    ];

  if isIgnored(namespace) || std.length(templateSetsFromLabel) < 1 then
    []
  else
    std.set(templateSetsFromLabel);

// Generate from Templates.
local generateTemplateMetadata(templateName, namespace) =
  config.templates[templateName] {
    metadata+: {
      namespace: namespace.metadata.name,
    },
  };

local generateTemplate(templateName, namespace) =
  generateTemplateMetadata(templateName, namespace) {
    metadata+: {
      annotations: config.rbacAnnotations,
      labels: config.rbacLabels,
    },
  } + config.templates[templateName];

local purgeTemplate(templateName, namespace) =
  esp.markForDelete(generateTemplateMetadata(templateName, namespace));

// Reconcile the given namespace.
local reconcileNamespace(namespace) =
  local desiredAvailableSets = std.set(std.filter(
    function(template) std.get(config.templates, template) != null,
    std.flattenArrays([
      config.templateSets[set]
      for set in desiredTemplateSets(namespace)
      if std.get(config.templateSets, set) != null
    ])
  ));
  // Generate array of RbacPolicies for the given policy set.
  [
    generateTemplate(template, namespace)
    for template in desiredAvailableSets
    // if cniMatches(policy) 🚨 pretty sure can be removed
  ]
  // Generate array of RbacPolicies to be deleted for the given policy set.
  +
  [
    purgeTemplate(template, namespace)
    for template in std.setDiff(activeTemplateSets(namespace), desiredAvailableSets)
    // if cniMatches(policy) 🚨 pretty sure can be removed
  ]
  // Generate annotation for the given namespace containing the new active policy sets.
  +
  [ {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: {
      annotations: {
        [activeSetsAnnotation]: std.manifestJsonMinified(desiredAvailableSets),
      },
      name: namespace.metadata.name,
    },
  } ];

// check if the object is getting deleted by checking if it has
// `metadata.deletionTimestamp`.
local inDelete(obj) = std.get(obj.metadata, 'deletionTimestamp', '') != '';

// Do the thing
if esp.triggerName() == 'namespace' then (
  // Handle single namespace update on namespace trigger
  local nsTrigger = esp.triggerData();
  // nsTrigger.resource can be null if we're called when the namespace is getting
  // deleted. If it's not null, we still don't want to do anything when the
  // namespace is getting deleted.
  if nsTrigger.resource != null && !inDelete(nsTrigger.resource) then
    reconcileNamespace(nsTrigger.resource)
) else if esp.triggerName() == 'role' || esp.triggerName() == 'rolebinding' then (
  // Handle single namespace update on role or rolebinding trigger
  local namespace = esp.triggerData().resourceEvent.namespace;
  std.flattenArrays([
    reconcileNamespace(ns)
    for ns in context.namespaces
    if ns.metadata.name == namespace && !inDelete(ns)
  ])
) else (
  // Reconcile all namespaces for jsonnetlibrary update or managedresource
  // reconcile.
  local namespaces = context.namespaces;
  std.flattenArrays([
    reconcileNamespace(ns)
    for ns in namespaces
    if !inDelete(ns)
  ])
  +
  legacyPolicyPurge
)
