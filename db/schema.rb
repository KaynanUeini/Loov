# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_04_07_222843) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "ai_insights", force: :cascade do |t|
    t.bigint "car_wash_id", null: false
    t.string "insight_type"
    t.text "content"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "owner_input"
    t.datetime "owner_input_at"
    t.text "previous_inputs"
    t.index ["car_wash_id"], name: "index_ai_insights_on_car_wash_id"
  end

  create_table "appointments", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "car_wash_id", null: false
    t.bigint "service_id", null: false
    t.datetime "scheduled_at"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "duration"
    t.string "payment_intent_client_secret"
    t.decimal "price_override", precision: 10, scale: 2
    t.boolean "walk_in", default: false, null: false
    t.string "walk_in_name"
    t.string "appointment_type", default: "regular", null: false
    t.datetime "acceptance_expires_at"
    t.decimal "prepayment_amount", precision: 10, scale: 2
    t.string "stripe_payment_intent_id"
    t.decimal "commission_amount", precision: 10, scale: 2
    t.integer "cancelled_by_id"
    t.string "cancellation_reason"
    t.string "cancelled_by_role"
    t.index ["acceptance_expires_at"], name: "index_appointments_on_acceptance_expires_at"
    t.index ["appointment_type"], name: "index_appointments_on_appointment_type"
    t.index ["cancelled_by_id"], name: "index_appointments_on_cancelled_by_id"
    t.index ["car_wash_id", "scheduled_at", "status"], name: "idx_appointments_overlap_check"
    t.index ["car_wash_id"], name: "index_appointments_on_car_wash_id"
    t.index ["service_id"], name: "index_appointments_on_service_id"
    t.index ["stripe_payment_intent_id"], name: "index_appointments_on_stripe_payment_intent_id", unique: true, where: "(stripe_payment_intent_id IS NOT NULL)"
    t.index ["user_id"], name: "index_appointments_on_user_id"
  end

  create_table "attendant_invitations", force: :cascade do |t|
    t.integer "car_wash_id"
    t.integer "inviter_id"
    t.integer "attendant_id"
    t.string "email"
    t.string "token"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "car_wash_closures", force: :cascade do |t|
    t.bigint "car_wash_id", null: false
    t.date "start_date"
    t.date "end_date"
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["car_wash_id"], name: "index_car_wash_closures_on_car_wash_id"
  end

  create_table "car_washes", force: :cascade do |t|
    t.string "name"
    t.string "address"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "latitude"
    t.decimal "longitude"
    t.integer "capacity_per_slot", default: 2, null: false
    t.string "cep"
    t.string "logradouro"
    t.string "bairro"
    t.string "cidade"
    t.string "uf"
    t.string "numero"
    t.integer "num_employees"
    t.boolean "active", default: true, null: false
    t.index ["active"], name: "index_car_washes_on_active"
    t.index ["user_id"], name: "index_car_washes_on_user_id"
  end

  create_table "loyalty_programs", force: :cascade do |t|
    t.bigint "car_wash_id", null: false
    t.integer "visits_required", default: 5, null: false
    t.string "reward_description", default: "Serviço gratuito", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["car_wash_id"], name: "index_loyalty_programs_on_car_wash_id"
  end

  create_table "monthly_costs", force: :cascade do |t|
    t.bigint "car_wash_id", null: false
    t.integer "year"
    t.integer "month"
    t.decimal "rent"
    t.decimal "salaries"
    t.decimal "utilities"
    t.decimal "products"
    t.decimal "maintenance"
    t.decimal "other_fixed"
    t.decimal "other_variable"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["car_wash_id"], name: "index_monthly_costs_on_car_wash_id"
  end

  create_table "operating_hours", force: :cascade do |t|
    t.bigint "car_wash_id", null: false
    t.integer "day_of_week"
    t.time "opens_at"
    t.time "closes_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["car_wash_id"], name: "index_operating_hours_on_car_wash_id"
  end

  create_table "owner_messages", force: :cascade do |t|
    t.bigint "car_wash_id", null: false
    t.bigint "sender_id", null: false
    t.bigint "recipient_id"
    t.string "body", null: false
    t.string "target", default: "all", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["car_wash_id", "created_at"], name: "index_owner_messages_on_car_wash_id_and_created_at"
    t.index ["car_wash_id"], name: "index_owner_messages_on_car_wash_id"
    t.index ["recipient_id", "created_at"], name: "index_owner_messages_on_recipient_id_and_created_at"
    t.index ["recipient_id"], name: "index_owner_messages_on_recipient_id"
    t.index ["sender_id"], name: "index_owner_messages_on_sender_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.decimal "amount"
    t.string "stripe_payment_id"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_charge_id"
    t.index ["appointment_id"], name: "index_payments_on_appointment_id"
  end

  create_table "pending_changes", force: :cascade do |t|
    t.integer "car_wash_id"
    t.integer "attendant_id"
    t.string "change_type"
    t.text "payload"
    t.string "status"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "appointment_id", null: false
    t.bigint "car_wash_id", null: false
    t.bigint "user_id", null: false
    t.integer "rating"
    t.string "tags"
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["appointment_id"], name: "index_reviews_on_appointment_id"
    t.index ["car_wash_id"], name: "index_reviews_on_car_wash_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "services", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.decimal "price"
    t.integer "duration"
    t.bigint "car_wash_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category"
    t.index ["car_wash_id"], name: "index_services_on_car_wash_id"
  end

  create_table "support_ticket_messages", force: :cascade do |t|
    t.bigint "support_ticket_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.boolean "from_admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["support_ticket_id"], name: "index_support_ticket_messages_on_support_ticket_id"
    t.index ["user_id"], name: "index_support_ticket_messages_on_user_id"
  end

  create_table "support_tickets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "car_wash_id"
    t.string "category", null: false
    t.text "description", null: false
    t.string "status", default: "open", null: false
    t.text "admin_reply"
    t.datetime "replied_at"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "agent_draft"
    t.datetime "agent_drafted_at"
    t.boolean "agent_sent", default: false, null: false
    t.index ["car_wash_id"], name: "index_support_tickets_on_car_wash_id"
    t.index ["status"], name: "index_support_tickets_on_status"
    t.index ["user_id"], name: "index_support_tickets_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "role", default: "client", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "full_name"
    t.string "phone"
    t.string "cpf"
    t.string "vehicle_model"
    t.string "stripe_customer_id"
    t.string "stripe_payment_method_id"
    t.string "stripe_card_last4"
    t.string "stripe_card_brand"
    t.datetime "blocked_at"
    t.index ["blocked_at"], name: "index_users_on_blocked_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
  end

  add_foreign_key "ai_insights", "car_washes"
  add_foreign_key "appointments", "car_washes"
  add_foreign_key "appointments", "services"
  add_foreign_key "appointments", "users"
  add_foreign_key "car_wash_closures", "car_washes"
  add_foreign_key "car_washes", "users"
  add_foreign_key "loyalty_programs", "car_washes"
  add_foreign_key "monthly_costs", "car_washes"
  add_foreign_key "operating_hours", "car_washes"
  add_foreign_key "owner_messages", "car_washes"
  add_foreign_key "owner_messages", "users", column: "recipient_id"
  add_foreign_key "owner_messages", "users", column: "sender_id"
  add_foreign_key "payments", "appointments"
  add_foreign_key "reviews", "appointments"
  add_foreign_key "reviews", "car_washes"
  add_foreign_key "reviews", "users"
  add_foreign_key "services", "car_washes"
  add_foreign_key "support_ticket_messages", "support_tickets"
  add_foreign_key "support_ticket_messages", "users"
  add_foreign_key "support_tickets", "car_washes"
  add_foreign_key "support_tickets", "users"
end
