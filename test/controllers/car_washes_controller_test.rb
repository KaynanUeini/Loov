require "test_helper"

class CarWashesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get car_washes_index_url
    assert_response :success
  end

  test "should get new" do
    get car_washes_new_url
    assert_response :success
  end

  test "should get create" do
    get car_washes_create_url
    assert_response :success
  end

  test "should get show" do
    get car_washes_show_url
    assert_response :success
  end

  test "should get edit" do
    get car_washes_edit_url
    assert_response :success
  end

  test "should get update" do
    get car_washes_update_url
    assert_response :success
  end
end
