local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.rbac;

local namespacedName(name, namespace='') = {
  local namespacedName = std.splitLimit(name, '/', 1),
  local ns = if namespace != '' then namespace else params.namespace,
  namespace: if std.length(namespacedName) > 1 then namespacedName[0] else ns,
  name: if std.length(namespacedName) > 1 then namespacedName[1] else namespacedName[0],
};

local processRole(r) = r {
  local extraRules = std.objectValues(
    com.getValueOrDefault(r, 'rules_', {})
  ),
  rules_:: null,
  rules+: [ {
    apiGroups: com.renderArray(rule.apiGroups),
    resources: com.renderArray(rule.resources),
    verbs: com.renderArray(rule.verbs),
  } for rule in extraRules ],
};

local processRoleBinding(rb) = rb {
  local extraSubjects = {
    users: [],
    serviceaccounts: [],
    groups: [],
  } + com.getValueOrDefault(rb, 'subjects_', {}),

  local rbNs = com.getValueOrDefault(rb.metadata, 'namespace', ''),


  roleRef+:
    {
      apiGroup: 'rbac.authorization.k8s.io',
    }
    +
    if std.objectHas(rb, 'role_') && std.objectHas(rb, 'clusterRole_') then error 'cannot specify both "role_" and "clusterRole_"'
    else if std.objectHas(rb, 'role_') then {
      kind: 'Role',
      name: rb.role_,
    }
    else if std.objectHas(rb, 'clusterRole_') then {
      kind: 'ClusterRole',
      name: rb.clusterRole_,
    }
    else {},

  role_:: null,
  clusterRole_:: null,

  subjects_:: null,
  subjects+:
    [ {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Group',
      name: g,
    } for g in com.renderArray(extraSubjects.groups) ]
    +
    [ {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'User',
      name: u,
    } for u in com.renderArray(extraSubjects.users) ]
    +
    [ {
      kind: 'ServiceAccount',
      namespace: namespacedName(sa, namespace=rbNs).namespace,
      name: namespacedName(sa, namespace=rbNs).name,
    } for sa in com.renderArray(extraSubjects.serviceaccounts) ],
};

{
  namespacedName: namespacedName,
  processRole: processRole,
  processRoleBinding: processRoleBinding,
}
