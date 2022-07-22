local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rbac;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('rbac', params.namespace);

{
  rbac: app,
}
