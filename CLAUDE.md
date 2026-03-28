# Loov — Marketplace de Lava-Rápidos

## Stack
- Ruby on Rails 7.1.5.1
- PostgreSQL
- Devise (autenticação)
- Sidekiq (jobs em background)
- Stripe Connect (pagamentos)
- Geocoder
- Importmap (sem Webpack)
- Resend (e-mails)

## Identidade visual
- Cor primária: lime green `#afff2d`
- Fontes: Bebas Neue (títulos) + DM Sans (corpo)
- Tema dark em todas as views

## Regras de desenvolvimento
- Sempre gerar arquivos COMPLETOS — nunca snippets parciais
- Nunca quebrar funcionalidades existentes ao modificar views
- Manter o padrão visual dark/lime em todas as telas
- Comentários em português

## Roles de usuário
- `client` — cliente final que agenda
- `owner` — proprietário do lava-rápido
- `attendant` — atendente (acesso limitado, sem financeiro)
- `admin` — admin da Loov (Kaynan)

## Modelo de negócio
- Agendamentos regulares: gratuitos para o lava-rápido
- Disponíveis: 5% de comissão sobre o valor total
- Fase de testes: gratuito para owners

## Admin
- URL: /admin/dashboard
- Usuário admin: kaynan_alves@hotmail.com (id: 1644)

## Repositório
- github.com/KaynanUeini/Loov
