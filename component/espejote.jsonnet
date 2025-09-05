local com = import 'lib/commodore.libjsonnet';
local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.rbac;

local esp_namespace = inv.parameters.espejote.namespace;
local mr_name = 'espejote-rbac-namespacesync';
local rbac_name = 'espejote-managedresource-rbac-namespacesync';

local namespacesync_rbac = [
  {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      labels: {
        'app.kubernetes.io/name': mr_name,
      },
      name: mr_name,
      namespace: esp_namespace,
    },
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      labels: {
        'app.kubernetes.io/name': rbac_name,
      },
      name: rbac_name,
    },
    rules: [
      {
        apiGroups: [ '' ],
        resources: [ 'namespaces' ],
        verbs: [ 'get', 'list' ],
      },
      {
        apiGroups: [ 'rbac.authorization.k8s.io' ],
        resources: [ 'clusterrolebindings', 'rolebindings' ],
        verbs: [ 'get', 'list', 'patch', 'create' ],
      },
    ],
  },
  {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      labels: {
        'app.kubernetes.io/name': rbac_name,
      },
      name: rbac_name,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: rbac_name,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: mr_name,
        namespace: esp_namespace,
      },
    ],
  },
];

local namespacesync_lib = esp.jsonnetLibrary(mr_name, esp_namespace) {
  spec: {
    data: {
      'namespacesyncs_v1.json': std.manifestJson({
        [name]: params.namespacesyncs[name]
        for name in std.objectFields(params.namespacesyncs)
      }),
    },
  },
};

local namespacesync_mr = esp.managedResource(mr_name, esp_namespace) {
  spec: {
    context: [
      {
        name: 'namespace',
        resource: {
          apiVersion: 'v1',
          kind: 'Namespace',
        },
      },
    ],
    triggers: [
      {
        name: 'jslib_rbac',
        watchResource: {
          apiVersion: namespacesync_lib.apiVersion,
          kind: 'JsonnetLibrary',
          name: namespacesync_lib.metadata.name,
          namespace: namespacesync_lib.metadata.namespace,
        },
      },
      {
        name: 'namespace',
        watchContextResource: {
          name: 'namespace',
        },
      },
    ],
  },
};

// Check if espejote is installed and resources are configured
local has_espejote_and_syncs = std.member(inv.applications, 'espejote') && std.length(params.namespacesyncs) > 0;

if has_espejote_and_syncs then
  {
    namespacesync_rbac: namespacesync_rbac,
    namespacesync_lib: namespacesync_lib,
    namespacesync_mr: namespacesync_mr,
  }
