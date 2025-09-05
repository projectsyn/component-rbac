local com = import 'lib/commodore.libjsonnet';
local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local utils = import 'utils.libsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.rbac;

local espNamespace = inv.parameters.espejote.namespace;
local mrName = 'espejote-rbac-sync';
local rbacName = 'espejote-managedresource-rbac-sync';

// RBAC for Espejote
// ℹ️ This might need cluster-admin permissions from the start.
local espejoteRBAC = [
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'rbac',
        'app.kubernetes.io/name': mrName,
      },
      name: mrName,
      namespace: espNamespace,
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'rbac',
        'app.kubernetes.io/name': rbacName,
      },
      name: rbacName,
    },
    rules: [
      {
        apiGroups: [ '' ],
        resources: [ 'namespaces' ],
        verbs: [ 'get', 'list', 'watch', 'patch' ],
      },
      {
        apiGroups: [ 'espejote.io' ],
        resources: [ 'jsonnetlibraries' ],
        resourceNames: [ mrName ],
        verbs: [ 'get', 'list', 'watch' ],
      },
      {
        apiGroups: [ 'rbac.authorization.k8s.io' ],
        resources: [ 'roles', 'rolebindings' ],
        verbs: [ 'get', 'list', 'watch', 'patch', 'create', 'delete' ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      labels: {
        'app.kubernetes.io/component': 'rbac',
        'app.kubernetes.io/name': rbacName,
      },
      name: rbacName,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: rbacName,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: mrName,
        namespace: espNamespace,
      },
    ],
  },
];

// Espejote resources
local _rbacAnnotations = {
  'syn.tools/source': 'https://github.com/projectsyn/component-rbac.git',
};
local _rbacLabels = {
  'app.kubernetes.io/managed-by': 'espejote',
  'app.kubernetes.io/part-of': 'syn',
  'app.kubernetes.io/component': 'rbac',
};

local prefixToAPI(name) =
  if std.startsWith(name, 'role/') then 'rbac.authorization.k8s.io/v1'
  else if std.startsWith(name, 'rolebinding/') then 'rbac.authorization.k8s.io/v1'
  // else if std.startsWith(name, 'serviceaccount/') then 'v1'
  else error 'Only prefixes "role/" and "rolebinding/" are supported.';
local prefixToKind(name) =
  if std.startsWith(name, 'role/') then 'Role'
  else if std.startsWith(name, 'rolebinding/') then 'RoleBinding'
  // else if std.startsWith(name, 'serviceaccount/') then 'ServiceAccount'
  else error 'Only prefixes "role/" and "rolebinding/" are supported.';
local suffixToName(name) = std.splitLimit(name, '/', 1)[1];

local jsonnetLibrary = esp.jsonnetLibrary(mrName, espNamespace) {
  spec: {
    data: {
      'config.json': std.manifestJson({
        // Resource Annotations and Labels,
        rbacAnnotations: _rbacAnnotations,
        rbacLabels: _rbacLabels,
        // Ignore namespaces by name or prefix
        ignoreNames: com.renderArray(params.namespaceSync.ignoreNames),
        ignorePrefixes: com.renderArray(params.namespaceSync.ignorePrefixes),
        // Templates and TemplateSets
        labelPrefix: params.namespaceSync.labelPrefix,
        templates: {
          [template]: {
                        apiVersion: prefixToAPI(template),
                        kind: prefixToKind(template),
                        metadata+: {
                          name: suffixToName(template),
                        },
                      } +
                      if prefixToKind(template) == 'Role' then utils.processRole(params.namespaceSync.templates[template])
                      else if prefixToKind(template) == 'RoleBinding' then utils.processRoleBinding(params.namespaceSync.templates[template])
                      else {}
          for template in std.objectFields(params.namespaceSync.templates)
          if params.namespaceSync.templates[template] != null
        },
        templateSets: {
          [set]: com.renderArray(params.namespaceSync.templateSets[set])
          for set in std.objectFields(params.namespaceSync.templateSets)
          if params.namespaceSync.templateSets[set] != null
        },
      }),
    },
  },
};

local managedResource = esp.managedResource(mrName, espNamespace) {
  metadata+: {
    annotations: {
      'syn.tools/description': |||
        Manages Roles and RoleBindings based on namespace labels.

        To customize the applied RBAC templates, you can use labels on namespaces to select
        additional template sets. See https://hub.syn.tools/rbac/index.html for details.
      |||,
    },
  },
  spec: {
    context: [
      {
        name: 'namespaces',
        resource: {
          apiVersion: 'v1',
          kind: 'Namespace',
        },
      },
    ],
    triggers: [
      {
        name: 'jslib',
        watchResource: {
          apiVersion: jsonnetLibrary.apiVersion,
          kind: 'JsonnetLibrary',
          name: jsonnetLibrary.metadata.name,
          namespace: jsonnetLibrary.metadata.namespace,
        },
      },
      {
        name: 'namespace',
        watchContextResource: {
          name: 'namespaces',
        },
      },
      {
        name: 'role',
        watchResource: {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'Role',
          labelSelector: {
            matchLabels: _rbacLabels,
          },
          namespace: '',
        },
      },
      {
        name: 'rolebinding',
        watchResource: {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'RoleBinding',
          labelSelector: {
            matchLabels: _rbacLabels,
          },
          namespace: '',
        },
      },
    ],
    serviceAccountRef: {
      name: espejoteRBAC[0].metadata.name,
    },
    applyOptions: {
      force: true,
    },
    template: importstr 'espejote-templates/rbac-sync.jsonnet',
  },
};

// Check if espejote is installed and resources are configured
local hasEspejote = std.member(inv.applications, 'espejote');
local hasTemplateSets = std.length(params.namespaceSync.templateSets) > 0;

// Define outputs below
if hasTemplateSets && hasEspejote then
  {
    espejote_rbac: espejoteRBAC,
    espejote_lib: jsonnetLibrary,
    espejote_mr: managedResource,
  }
else if hasTemplateSets then
  std.trace(
    'espejote must be installed',
    {}
  )
else {}
