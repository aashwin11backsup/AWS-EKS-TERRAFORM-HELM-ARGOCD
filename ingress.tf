# Creating Ingress ,acting as "blueprint" that the AWS Load Balancer Controller will act on....
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server-ingress"
    namespace = "argocd"

    annotations = {
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"  # ALB will be public
      "alb.ingress.kubernetes.io/target-type" = "ip"               # Targets are pod IPs
    }
  }

  spec {
    ingress_class_name = "alb"  # Must match the ALB ingress controller class

    default_backend {
      service {
        name = "argocd-server"  # Your Argo CD server service
        port {
          number = 80
        }
      }
    }
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
helm_release.argocd
 
  ]
}


# IMP: The ALB created will be auto deleted when we do terraform destroy
# Because, Terraform sees the kubernetes_ingress_v1 resource in its state and sends a command to the Kubernetes API to delete that Ingress resource.
# The AWS Load Balancer Controller sees that the Ingress resource it was responsible for has been deleted.
# Hence,  It then makes its own API calls to AWS to delete the ALB and the Target Group

# UPDATE: Faced issue while using terraform destroy
# ------> THIS ISSUE WILL COME ONLY WHEN ""the AWS Load Balancer Controller is deleted before the Ingress resources."

# We can get the DNS Name using the command:
# ----> kubectl get ingress -n argocd

# Check if the ALB points to the ArgoCD server as Target Group:
# ---> kubectl describe ingress argocd-server-ingress -n argocd
# OUTPUT: It will give default backend: "Default backend:  argocd-server:80 (10.x.xxx.xxx:xxxx)"
# This will show the POD IP 
# Recheck if the IP is same using command:
# kubectl get endpoints argocd-server -n argocd
# OUTPUT: it will be same as above:(10.x.xxx.xxx:xxxx)


#Also check using curl command:
# ----> curl http://alb-dns-name

#Use the command to generate the password:
#----> kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d



