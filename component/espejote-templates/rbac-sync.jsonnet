local esp = import 'espejote.libsonnet';
local trigger = esp.triggerData();

local config = import 'lib/espejote-rbac-sync/clusterroles_v1.json.json';

local inDelete(obj) = std.get(obj.metadata, 'deletionTimestamp', '') != '';
local role_binding(ns) = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'RoleBinding',
  metadata: {
    name: 'ga-lotse-logviewer',
    namespace: ns,
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'view',
  },
  subjects: [ {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'Group',
    name: 'ga-lotse-logviewer',
  } ],
};

// TODO: We also need a way to remove a RoleBinding if the label is removed from the namespace
if esp.triggerName() == 'namespace' && !inDelete(trigger.resource) then
  // if the trigger is 'namespace', render single namespace
  role_binding(trigger.resource.metadata.name)
else [
  // if the trigger is not 'namespace', render all labeled namespaces
  role_binding(ns.metadata.name)
  for ns in esp.context().galotse_ns
  if !inDelete(ns)
]
