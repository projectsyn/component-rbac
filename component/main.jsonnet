local com = import 'lib/commodore.libjsonnet';
// main template for rbac
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.rbac;

local namespacedName(name, namespace='') = {
  local namespacedName = std.splitLimit(name, '/', 1),
  local ns = if namespace != '' then namespace else params.namespace,
  namespace: if std.length(namespacedName) > 1 then namespacedName[0] else ns,
  name: if std.length(namespacedName) > 1 then namespacedName[1] else namespacedName[0],
};

{

  serviceaccounts: com.generateResources(
    params.serviceaccounts,
    function(name) kube.ServiceAccount(namespacedName(name).name) {
      metadata+: {
        namespace: namespacedName(name).namespace,
      },
    }
  ),
  clusterRoles: com.generateResources(params.clusterroles, kube.ClusterRole),
  clusterRoleBindings: com.generateResources(params.clusterrolebindings, function(name) kube._Object('rbac.authorization.k8s.io/v1', 'ClusterRoleBinding', name)),
  roles: com.generateResources(
    params.roles,
    function(name) kube.Role(namespacedName(name).name) {
      metadata+: {
        namespace: namespacedName(name).namespace,
      },
    }
  ),
  roleBindings: com.generateResources(
    params.rolebindings,
    function(name) kube._Object('rbac.authorization.k8s.io/v1', 'RoleBinding', namespacedName(name).name) {
      metadata+: {
        namespace: namespacedName(name).namespace,
      },
    }
  ),
}
