class AddItemsToAttendantActivities < ActiveRecord::Migration[7.1]
  def change
    add_column :attendant_activities, :items, :text
  end
end
