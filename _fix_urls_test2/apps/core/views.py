from __future__ import annotations

"""Vues template CBV (accueil + back-office HTMX).

Toute logique metier passe par services / selectors — pas de duplication Ninja.
"""

from django.http import Http404, HttpRequest, HttpResponse, JsonResponse
from django.shortcuts import render
from django.views import View
from django.views.generic import TemplateView
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin

from . import selectors, services


class StaffRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    '''Exige un utilisateur authentifie avec is_staff.

    MRO:
    1. LoginRequiredMixin.dispatch -> redirection login si anonyme
    2. UserPassesTestMixin.dispatch -> 403 si non staff
    3. Vue concrete (get/post)
    '''

    login_url = "/accounts/login/"
    redirect_field_name = "next"

    def test_func(self) -> bool:
        user = self.request.user
        return bool(user.is_authenticated and user.is_staff)


class HomeView(View):
    '''Racine Django (UI produit Astro sur :4321).

    MRO:
    1. View.get -> JsonResponse d'information API / liens staff
    '''

    def get(self, request: HttpRequest) -> JsonResponse:
        return JsonResponse(
            {
                "service": "core",
                "frontend": "http://localhost:4321",
                "backoffice": "/backoffice/",
                "health": "/api/health/",
            }
        )


class BackofficeListView(StaffRequiredMixin, TemplateView):
    '''Liste filtrable du back-office (plein page ou partial HTMX).

    MRO:
    1. StaffRequiredMixin.dispatch -> auth + is_staff
    2. TemplateView.get -> contexte items + query
    3. get_template_names -> partial _item_list si request.htmx
    '''

    template_name = "backoffice/list.html"
    partial_template_name = "backoffice/partials/_item_list.html"

    def get_template_names(self) -> list[str]:
        if getattr(self.request, "htmx", False) and self.request.htmx:
            return [self.partial_template_name]
        return [self.template_name]

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        query = (self.request.GET.get("q") or "").strip()
        context["query"] = query
        context["items"] = selectors.list_staff_demo_items(query=query)
        return context


class BackofficeDetailView(StaffRequiredMixin, TemplateView):
    '''Detail d'un element demo (partial HTMX ou page minimale).

    MRO:
    1. StaffRequiredMixin.dispatch -> auth + is_staff
    2. TemplateView.get -> item via selector
    '''

    template_name = "backoffice/partials/_item_detail.html"

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        item_id = int(self.kwargs["pk"])
        item = selectors.get_staff_demo_item(item_id)
        if item is None:
            raise Http404("Element introuvable")
        context["item"] = item
        return context


class BackofficePingView(StaffRequiredMixin, View):
    '''Mutation demo HTMX : ping workspace via service.

    MRO:
    1. StaffRequiredMixin.dispatch -> auth + is_staff
    2. View.post -> services.ping_staff_workspace + partial flash
    '''

    def post(self, request: HttpRequest) -> HttpResponse:
        result = services.ping_staff_workspace()
        return render(
            request,
            "backoffice/partials/_flash.html",
            {"message": result["message"]},
        )