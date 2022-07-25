local com = import 'lib/commodore.libjsonnet';
// main template for rbac
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.rbac;


{
  serviceaccounts: com.generateResources(params.serviceaccounts, kube.ServiceAccount),
  clusterRoles: com.generateResources(params.clusterroles, kube.ClusterRole),
  clusterRoleBindings: com.generateResources(params.clusterrolebindings, function(name) kube._Object('rbac.authorization.k8s.io/v1', 'ClusterRoleBinding', name)),
  roles: com.generateResources(params.roles, kube.Role),
  roleBindings: com.generateResources(params.rolebindings, function(name) kube._Object('rbac.authorization.k8s.io/v1', 'RoleBinding', name)),
}
