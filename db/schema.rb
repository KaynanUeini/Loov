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

ActiveRecord::Schema[7.1].define(version: 2026_03_10_233523) do
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
    t.index ["car_wash_id"], name: "index_appointments_on_car_wash_id"
    t.index ["service_id"], name: "index_appointments_on_service_id"
    t.index ["user_id"], name: "index_appointments_on_user_id"
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
    t.index ["user_id"], name: "index_car_washes_on_user_id"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "ai_insights", "car_washes"
  add_foreign_key "appointments", "car_washes"
  add_foreign_key "appointments", "services"
  add_foreign_key "appointments", "users"
  add_foreign_key "car_washes", "users"
  add_foreign_key "monthly_costs", "car_washes"
  add_foreign_key "operating_hours", "car_washes"
  add_foreign_key "payments", "appointments"
  add_foreign_key "reviews", "appointments"
  add_foreign_key "reviews", "car_washes"
  add_foreign_key "reviews", "users"
  add_foreign_key "services", "car_washes"
end
