#!/usr/bin/env python3
"""
Roda na raiz do projeto: python3 aplicar_back_buttons.py
Aplica o botao de voltar padronizado em todos os arquivos.
"""

import re

def insert_before_line(filepath, line_num, new_content):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    lines.insert(line_num - 1, new_content + '\n')
    with open(filepath, 'w') as f:
        f.writelines(lines)
    print(f"  [OK] {filepath} — inserido na linha {line_num}")

def replace_block(filepath, old, new):
    with open(filepath, 'r') as f:
        content = f.read()
    if old in content:
        content = content.replace(old, new, 1)
        with open(filepath, 'w') as f:
            f.write(content)
        print(f"  [OK] {filepath} — bloco substituido")
    else:
        print(f"  [AVISO] {filepath} — bloco nao encontrado, pular")

def delete_block(filepath, old):
    replace_block(filepath, old, '')

# ── 1. car_washes/index.html.erb ─────────────────────────────────────────────
print("\n1. car_washes/index.html.erb")

# Remove CSS .back-link
delete_block(
    'app/views/car_washes/index.html.erb',
    """  /* ── BACK ────────────────────────────────────────────── */
  .back-link {
    display: inline-flex; align-items: center; gap: .45rem;
    font-size: .8rem; color: var(--text-muted); text-decoration: none;
    transition: color .2s ease; margin-bottom: 2.5rem; cursor: none;
  }
  .back-link:hover { color: var(--lime); }

"""
)

# Substitui link_to back-link pelo partial
replace_block(
    'app/views/car_washes/index.html.erb',
    """    <%= link_to root_path, class: "back-link" do %>
      <i class="fas fa-arrow-left"></i> Voltar
    <% end %>""",
    "    <%= render 'layouts/back_button', path: root_path %>"
)

# ── 2. car_washes/manage.html.erb ────────────────────────────────────────────
print("\n2. car_washes/manage.html.erb")
insert_before_line(
    'app/views/car_washes/manage.html.erb',
    347,
    "<%= render 'layouts/back_button', path: car_wash_path(@car_wash) %>\n"
)

# ── 3. disponivel/index.html.erb ─────────────────────────────────────────────
print("\n3. disponivel/index.html.erb")
insert_before_line(
    'app/views/disponivel/index.html.erb',
    116,
    "<%= render 'layouts/back_button', path: root_path %>\n"
)

# ── 4. disponivel/checkout.html.erb ──────────────────────────────────────────
print("\n4. disponivel/checkout.html.erb")
insert_before_line(
    'app/views/disponivel/checkout.html.erb',
    82,
    "<%= render 'layouts/back_button', path: disponivel_index_path %>\n"
)

# ── 5. owner/car_wash_appointments/index.html.erb ────────────────────────────
print("\n5. owner/car_wash_appointments/index.html.erb")
insert_before_line(
    'app/views/owner/car_wash_appointments/index.html.erb',
    246,
    "<%= render 'layouts/back_button', path: root_path %>\n"
)

# ── 6. owner/car_wash_appointments/show.html.erb ─────────────────────────────
print("\n6. owner/car_wash_appointments/show.html.erb")
insert_before_line(
    'app/views/owner/car_wash_appointments/show.html.erb',
    224,
    "<%= render 'layouts/back_button', path: owner_car_wash_appointments_path %>\n"
)
# Remove btn-back de dentro da div .actions
replace_block(
    'app/views/owner/car_wash_appointments/show.html.erb',
    """      <%= link_to owner_car_wash_appointments_path, class: "btn-back" do %>
        <i class="fas fa-arrow-left"></i> Voltar
      <% end %>""",
    ""
)

# ── 7. owner/financial_tracking/index.html.erb ───────────────────────────────
print("\n7. owner/financial_tracking/index.html.erb")
insert_before_line(
    'app/views/owner/financial_tracking/index.html.erb',
    377,
    "<%= render 'layouts/back_button', path: root_path %>\n"
)
# Remove btn-back do final
delete_block(
    'app/views/owner/financial_tracking/index.html.erb',
    """    <%= link_to owner_car_wash_appointments_path, class: "btn-back" do %>
      <i class="fas fa-arrow-left"></i> Agendamentos
    <% end %>"""
)

# ── 8. owner/monthly_costs/index.html.erb ────────────────────────────────────
print("\n8. owner/monthly_costs/index.html.erb")
insert_before_line(
    'app/views/owner/monthly_costs/index.html.erb',
    246,
    "<%= render 'layouts/back_button', path: root_path %>\n"
)

# ── 9. owner/monthly_costs/edit.html.erb ─────────────────────────────────────
print("\n9. owner/monthly_costs/edit.html.erb")
insert_before_line(
    'app/views/owner/monthly_costs/edit.html.erb',
    206,
    "<%= render 'layouts/back_button', path: owner_monthly_costs_path %>\n"
)

# ── 10. client/profiles/edit.html.erb ────────────────────────────────────────
print("\n10. client/profiles/edit.html.erb")
insert_before_line(
    'app/views/client/profiles/edit.html.erb',
    276,
    "<%= render 'layouts/back_button', path: root_path %>\n"
)

print("\n✅ Concluido! Verifique o resultado com: rails s")
